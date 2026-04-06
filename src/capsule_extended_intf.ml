open! Base

(** For now, see the {!Capsule_expert} library for high-level documentation of capsule
    types.

    This module provides an interface to capsules that is a small subset of
    [Capsule_expert], starting with the most common entry points. The interface is also
    cleaned up to be somewhat easier to use, and more consistent with other conventions in
    [Base].

    Over time we will provide more of [Capsule_expert]'s functionality. *)
module type Capsule = sig @@ portable
  module Capsule := Capsule_expert

  module Access : sig
    type 'k t = 'k Capsule.Access.t
    type packed = Capsule.Access.packed = P : 'k t -> packed [@@unboxed]
    type 'k boxed = 'k Capsule.Access.boxed

    (** Obtain an [Access.t] for the current capsule. Since we do not know the brand for
        the current capsule, we receive a fresh one. *)
    val current : unit -> packed @@ portable

    val unbox : 'k boxed -> 'k t @@ portable
    val box : 'k t -> 'k boxed @@ portable
  end

  module Data : sig
    type ('a, 'k) t = ('a, 'k) Capsule.Data.t

    (** These functions are the most common way to interact with capsules. *)

    val%template create : (unit -> 'a @ u) @ local once portable -> ('a, 'k) t @ u
    [@@mode u = (unique, aliased)]

    [%%template:
    [@@@mode.default l = (global, local)]

    val wrap : access:'k Access.t -> 'a @ l -> ('a, 'k) t @ l

    val unwrap
      : ('a : value mod p) 'k.
      access:'k Access.t @ c -> ('a, 'k) t @ l -> 'a @ c l
    [@@mode l = l, (c, p) = ((uncontended, nonportable), (shared, portable))]

    (** These functions enable more complicated manipulation of capsules. *)

    val return : ('a : value mod contended) @ l portable -> ('a, 'k) t @ l
    val both : ('a, 'k) t @ l -> ('b, 'k) t @ l -> ('a * 'b, 'k) t @ l
    val fst : ('a * _, 'k) t @ l -> ('a, 'k) t @ l
    val snd : (_ * 'b, 'k) t @ l -> ('b, 'k) t @ l

    (** Retrieve the value in a capsule directly. Likely only useful if the capsule has
        already been [map]'d, as capsules do not usually contain portable values. *)
    val get_id : ('a : value mod portable) 'k. ('a, 'k) t @ l -> 'a @ contended l]
  end

  module Isolated : sig
    type%template ('a, 'k) inner =
      #{ data : ('a, 'k) Data.t @@ u
       ; key : 'k Capsule.Key.t
       }
    [@@modality.explicit u = (unique, aliased)]

    type%template ('a, 'k) inner = (('a, 'k) inner[@modality.explicit aliased])

    [%%template:
    [@@@mode.default u = (unique, aliased)]

    (** A value isolated within its own capsule.

        A primary use-case for this type is to use aliasing as a proxy for contention.
        [unique] access to an ['a Capsule.Isolated.t] allows [uncontended] access to the
        underlying ['a]. [aliased] access to an ['a Capsule.Isolated.t] allows [shared]
        access to the underlying ['a].

        This type is templated over the uniqueness of the underlying ['a], defaulting to
        the [aliased] mode. So if you have a ['a Capsule.Isolated.t @ unique], you can
        only access the inner ['a @ aliased], but if you have an
        [('a Capsule.Isolated.t[@mode unique]) @ unique], you can access the inner
        ['a @ unique] *)
    type 'a t = P : (('a, 'k) inner[@mode u]) -> ('a t[@mode u]) [@@unboxed]

    (** A boxed representation of {{!t} an isolated value}. *)
    type 'a boxed : value mod contended portable

    val box : ('a t[@mode u]) @ unique -> ('a boxed[@mode u]) @ unique
    val unbox : ('a boxed[@mode u]) @ unique -> ('a t[@mode u]) @ unique
    val box_aliased : ('a t[@mode u]) -> ('a boxed[@mode u])
    val unbox_aliased : ('a boxed[@mode u]) -> ('a t[@mode u])

    (** [create f] runs [f] within a fresh capsule, and creates a [Capsule.Isolated.t]
        containing the result. *)
    val create : (unit -> 'a @ u) @ local once portable -> ('a t[@mode u]) @ unique

    (** [with_shared t ~f] takes an [aliased] isolated capsule [t], calls [f] with shared
        access to its value, and returns the result of [f]. *)
    val with_shared
      : ('a : value mod portable) 'b.
      ('a t[@mode u])
      -> f:('a @ shared -> 'b @ contended portable) @ local once portable
      -> 'b @ contended portable

    [@@@mode.default l = (global, local)]

    (** [unwrap t ~f] takes a [unique] isolated capsule [t] and returns the underlying
        value, merging the capsule with the current capsule. *)
    val unwrap : ('a t[@mode u]) @ l unique -> 'a @ l u

    (** [unwrap_shared t ~f] takes an [aliased] isolated capsule [t] and returns the
        underlying value at [shared]. *)
    val unwrap_shared : ('a : value mod portable). ('a t[@mode u]) @ l -> 'a @ l shared]

    (*_ Note that the following functions rely on the fact that the inner ['a] is aliased,
        so only work on the version of [t] with aliased data. *)

    (** Project out a contended reference to the underlying value from a unique [t],
        returning the unique [t] back alongside the alias to the underlying value. *)
    val get_id
      : ('a : value mod portable).
      'a t @ unique -> #('a t * 'a Modes.Aliased.t) @ contended unique

    (** [with_unique t ~f] takes a [unique] isolated capsule [t], calls [f] with its
        value, and returns a tuple of the unique isolated capsule and the result of [f]. *)
    val with_unique
      : 'a ('b : value mod contended portable).
      'a t @ unique
      -> f:('a -> 'b) @ local once portable
      -> #('a t * 'b Modes.Aliased.t) @ unique

    (** Like [with_unique], but with the most general mode annotations. *)
    val with_unique_gen
      :  'a t @ unique
      -> f:('a -> 'b @ contended portable unique) @ local once portable
      -> #('a t * 'b) @ contended portable unique
  end

  module Guard : sig
    type ('a, 'k) inner =
      #{ data : ('a, 'k) Data.t @@ global
       ; password : 'k Capsule.Password.t
       }

    (** An encapsulated value accessible for the duration of the current region.

        A value of type ['a Guard.t] provides [uncontended] access to the underlying ['a]
        over a local scope. *)
    type 'a t = P : ('a, 'k) inner -> 'a t [@@unboxed]

    (** [with_ a ~f] calls [f] with a [local] {!Guard.t} representing local access to [a],
        which lives in the current capsule. *)
    val with_ : 'a -> f:('a t @ local -> 'b) @ local once -> 'b

    (** [get t ~f] computes a value using the data accessible via [t]. *)
    val get
      :  'a t @ local
      -> f:('a -> 'b @ contended portable) @ local once portable
      -> 'b @ contended portable

    (** Like [get], but for for functions that return [unit]. *)
    val iter : 'a t @ local -> f:('a -> unit) @ local once portable -> unit

    (** Construct a new [t] by mapping a function over the referenced value. *)
    val map : 'a t @ local -> f:('a -> 'b) @ local once portable -> 'b t @ local

    module Shared : sig
      type ('a, 'k) inner =
        #{ data : ('a shared, 'k) Data.t @@ global
         ; password : 'k Capsule.Password.Shared.t
         }

      (** An encapsulated value that may be read for the duration of the current region.

          A value of type ['a Shared.t] provides [shared] access to the underlying ['a]
          over a local scope. A [forkable] ['a Shared.t] can be captured by functions that
          run on other domains. *)
      type 'a t = P : ('a, 'k) inner -> 'a t [@@unboxed]

      (** [with_ a ~f] calls [f] with a [local forkable] {!Shared.t} representing local
          read-only access to [a], which is readable in the current capsule. *)
      val with_
        : ('a : value mod portable) 'b.
        'a @ shared -> f:('a t @ forkable local -> 'b) @ forkable local once -> 'b

      (** [get t ~f] computes a value using data accessible via [t]. *)
      val get
        : ('a : value mod portable) 'b.
        'a t @ local
        -> f:('a @ shared -> 'b @ contended portable) @ local once portable
        -> 'b @ contended portable

      (** Like [get], but for for functions that return [unit]. *)
      val iter
        : ('a : value mod portable).
        'a t @ local -> f:('a @ shared -> unit) @ local once portable -> unit

      (** Construct a new [t] by mapping a function over the referenced value. *)
      val map
        : ('a : value mod portable) ('b : value mod portable).
        'a t @ local
        -> f:('a @ shared -> 'b @ shared) @ local once portable
        -> 'b t @ local

      module Uncontended : sig
        (** Like ['a Shared.t], but allows read-only computations to return an uncontended
            result in the current capsule. *)
        type ('a, 'k) t = ('a, 'k) inner =
          #{ data : ('a shared, 'k) Data.t @@ global
           ; password : 'k Capsule.Password.Shared.t
           }

        type ('a, 'b) f =
          { f : 'k. ('a, 'k) t @ forkable local -> ('b, 'k) Capsule.Data.Shared.t }

        (** [with_ a ~f] calls [f] with a [local forkable] {!Uncontended.t} representing
            local read-only access to [a], which is readable in the current capsule.

            The result of [f] is a [Capsule.Data.Shared.t], which can be unwrapped in the
            current capsule. *)
        val with_ : 'a @ shared -> ('a, 'b) f @ forkable local once -> 'b

        (** [get t ~f] computes a value using data accessible via [t]. *)
        val get
          : ('a : value mod portable) 'b 'k.
          ('a, 'k) t @ local
          -> f:('a @ shared -> 'b) @ local once portable
          -> ('b, 'k) Capsule.Data.Shared.t

        (** Construct a new [t] by mapping a function over the referenced value. *)
        val map
          : ('a : value mod portable) ('b : value mod portable) 'k.
          ('a, 'k) t @ local
          -> f:('a @ shared -> 'b @ shared) @ local once portable
          -> ('b, 'k) t @ local
      end
    end
  end

  module (Initial @@ nonportable) : sig
    (** The initial capsule, i.e. the implicit capsule associated with the initial domain.
        This is the capsule in which library top-levels run, and so [nonportable]
        top-level functions are allowed to access it. *)

    (** The brand for the initial capsule. *)
    type k = Capsule.initial

    (** Access to the initial capsule *)
    val access : k Access.t

    module Data : sig
      (** A value in the initial capsule. *)
      type 'a t = ('a, k) Data.t [@@deriving sexp]

      [%%template:
      [@@@mode.default l = (global, local)]

      (** Store a value in a [Capsule.Data.t] for the initial capsule. This function is
          [nonportable], requiring it to be run from the initial domain. *)
      val wrap : 'a @ l -> 'a t @ l

      (** Extract a value from a [Capsule.Data.t] for the initial capsule. This function
          is [nonportable], requiring it to be run from the initial domain. *)
      val unwrap : 'a t @ l -> 'a @ l]
    end
  end
end
