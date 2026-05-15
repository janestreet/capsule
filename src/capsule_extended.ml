open! Base
module Expert = Capsule_expert

module Access = struct
  type 'k t = 'k Expert.Access.t
  type packed = Expert.Access.packed = P : 'k t -> packed [@@unboxed]
  type 'k boxed = 'k Expert.Access.boxed

  let current = Expert.current
  let unbox = Expert.Access.unbox
  let box = Expert.Access.box
end

module Data = struct
  type ('a, 'k) t = ('a, 'k) Expert.Data.t

  let create = Expert.Data.create
  let wrap = Expert.Data.wrap
  let unwrap = Expert.Data.unwrap
  let%template[@mode global shared] unwrap = Expert.Data.unwrap_shared
  let return = Expert.Data.inject
  let get_id = Expert.Data.project
  let project_shared = Expert.Data.project_shared
  let both = Expert.Data.both
  let fst = Expert.Data.fst
  let snd = Expert.Data.snd

  [%%template
  [@@@mode.default unique]

  let create = Expert.Data.create_unique
  let unwrap = Expert.Data.unwrap_unique]

  [%%template
  [@@@mode.default local]

  let wrap = Expert.Data.Local.wrap
  let unwrap = Expert.Data.Local.unwrap
  let[@mode local shared] unwrap = Expert.Data.Local.unwrap_shared
  let return = Expert.Data.Local.inject
  let get_id = Expert.Data.Local.project
  let both = Expert.Data.Local.both
  let fst = Expert.Data.Local.fst
  let snd = Expert.Data.Local.snd]
end

module Initial = struct
  type k = Expert.initial

  let access = Expert.initial

  module Data = struct
    type 'a t = ('a, k) Data.t

    [%%template
    [@@@mode.default l = (global, local)]

    let wrap a = (Data.wrap [@mode l]) ~access a [@exclave_if_local l]
    let unwrap a = (Data.unwrap [@mode l]) ~access a [@exclave_if_local l]]

    let sexp_of_t sexp_of_a t = sexp_of_a (unwrap t)
    let t_of_sexp a_of_sexp a = wrap (a_of_sexp a)
  end
end

module%template Isolated = struct
  module Repr = struct
    type ('a, 'k) inner =
      { data : ('a, 'k) Data.t
      ; key : 'k Expert.Key.t
      }

    type 'a t = P : ('a, 'k) inner -> 'a t [@@unboxed]
  end

  (* We use this type declaration just as justification for the kind annotation on ['a t]. *)
  type ('a, 'k) _inner = ('a, 'k) Repr.inner
  type 'a t

  [@@@mode.default.explicit u = (unique, aliased)]

  external unsafe_to_data
    :  ('a t[@local_opt])
    -> (('a, 'k) Data.t[@local_opt])
    = "%identity"

  external unsafe_of_data
    :  (('a, 'k) Data.t[@local_opt])
    -> ('a t[@local_opt])
    = "%identity"

  let to_repr t =
    let (P key) = Expert.create () in
    let data = (unsafe_to_data [@mode.explicit u]) t in
    Repr.P { data; key }
  ;;

  let of_repr (Repr.P { data; key = _ }) = (unsafe_of_data [@mode.explicit u]) data
end

module%template Frozen = struct
  type 'a t = 'a portable Isolated.t

  let to_repr = (Isolated.to_repr [@mode.explicit aliased])
  let of_repr = (Isolated.of_repr [@mode.explicit aliased])

  let create f =
    let (P key) = Expert.create () in
    let data = Data.create (fun () -> { portable = f () }) in
    of_repr (P { key; data })
  ;;

  let unwrap t =
    let (P { key; data }) = to_repr t in
    (Data.project_shared ~key data).portable
  ;;
end

module%template Owned = struct
  type 'a t = 'a Isolated.t

  let to_repr = (Isolated.to_repr [@mode.explicit unique])
  let of_repr = (Isolated.of_repr [@mode.explicit unique])

  let create f =
    let (P key) = Expert.create () in
    let data = (Data.create [@mode unique]) f in
    of_repr (P { key; data })
  ;;

  let freeze t =
    let open struct
      (*_ Safe because ['a = 'a portable] for ('a : value mod portable) *)
      external wrap_portable
        : 'a 'k.
        ('a, 'k) Expert.Data.t -> ('a portable, 'k) Expert.Data.t
        = "%identity"
    end in
    let (P { data; key }) = (Isolated.to_repr [@mode.explicit aliased]) t in
    let data = wrap_portable data in
    (Isolated.of_repr [@mode.explicit aliased]) (P { data; key })
  ;;

  let unwrap t =
    let (P { key; data }) = to_repr t in
    let access = Expert.Key.destroy key in
    (Data.unwrap [@mode unique]) ~access data
  ;;

  let dup (type a) (t : a) : a * a = t, t

  let get_contended (type a) (t : a t) : a t * a =
    let (P { data; key }) = to_repr t in
    let data, data' = dup data in
    let t = of_repr (P { data; key }) in
    t, Data.get_id data'
  ;;

  let with_ (type a) (t : a t) ~f =
    let (P { key; data }) = to_repr t in
    let data, data' = dup data in
    let result, key =
      Expert.Key.access key ~f:(fun access ->
        { many = f (Expert.Data.unwrap ~access data') })
    in
    let t = of_repr (P { key; data }) in
    t, result.many
  ;;
end

module Scoped = struct
  type ('a, 'k) inner =
    { data : ('a, 'k) Data.t
    ; password : 'k Expert.Password.t
    }

  type 'a t = P : ('a, 'k) inner -> 'a t [@@unboxed]

  let[@inline] with_ a ~f =
    let (P access) = Access.current () in
    let data = Data.wrap ~access a in
    (Expert.Password.with_current access (fun password ->
       { aliased_many = { global = f (P { data; password }) } }))
      .aliased_many
      .global
  ;;

  let[@inline] get (P { data; password }) ~f =
    (Expert.Data.extract data ~password ~f:(fun a -> { many = { aliased = f a } })).many
      .aliased
  ;;

  let iter = get

  let[@inline] map (P { data; password }) ~f =
    P { data = Expert.Data.map data ~password ~f; password }
  ;;

  module Shared = struct
    type ('a, 'k) inner =
      { data : ('a shared, 'k) Data.t
      ; password : 'k Expert.Password.Shared.t
      }

    type 'a t = P : ('a, 'k) inner -> 'a t [@@unboxed]

    module Uncontended = struct
      type ('a, 'k) t = ('a, 'k) inner =
        { data : ('a shared, 'k) Data.t
        ; password : 'k Expert.Password.Shared.t
        }

      type ('a, 'b) f = { f : 'k. ('a, 'k) inner -> ('b, 'k) Expert.Data.Shared.t }

      let[@inline] with_ data { f } =
        let (P access) = Access.current () in
        let data = Data.wrap ~access { shared = data } in
        let { many = { global = { aliased = data } } } =
          Expert.Password.with_current access (fun [@inline] password ->
            let password = Expert.Password.shared password in
            { many =
                Expert.Password.Shared.borrow password (fun [@inline] password ->
                  { global = { aliased = f { data; password } } })
            })
        in
        Expert.Data.Shared.unwrap ~access data
      ;;

      let[@inline] get { data; password } ~f =
        Expert.Data.Shared.map_into data ~password ~f:(fun [@inline] { shared } ->
          f shared)
        [@nontail]
      ;;

      let[@inline] map { data; password } ~f =
        { data =
            Expert.Data.map_shared data ~password ~f:(fun [@inline] { shared } ->
              { shared = f shared })
        ; password
        }
      ;;
    end

    let[@inline] with_ data ~f =
      let (P access) = Access.current () in
      let data = Data.wrap ~access { shared = data } in
      (Expert.Password.with_current access (fun [@inline] password ->
         let password = Expert.Password.shared password in
         { many =
             Expert.Password.Shared.borrow password (fun [@inline] password ->
               { global = { aliased = f (P { data; password }) } })
         }))
        .many
        .global
        .aliased
    ;;

    let[@inline] get (P t) ~f =
      (Expert.Data.Shared.project
         (Uncontended.get t ~f:(fun [@inline] a -> { portended = f a })))
        .portended
    ;;

    let iter = get
    let[@inline] map (P t) ~f = P (Uncontended.map t ~f)
  end
end
