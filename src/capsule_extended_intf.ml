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

    [%%template:
      val idx : ('a, 'k) t @ l -> ('a, 'b) idx_imm -> ('b, 'k) t @ l
      [@@ocaml.doc
        {| [idx t i] is a pointer to the value at [i] in [t].

          See {!Ox.Idx} for more information on indexes. |}]
      [@@mode l = (global, local)]]
  end

  module Isolated : sig
    (** The underlying representation of both [Frozen.t] and [Owned.t]. *)
    module Repr : sig
      type ('a, 'k) inner =
        #{ data : ('a, 'k) Data.t
         ; key : 'k Capsule.Key.t
         }

      type 'a t = P : ('a, 'k) inner -> 'a t [@@unboxed]
    end
  end

  module Frozen : sig
    (** A frozen value in its own capsule. Nobody may write to the contained ['a], so
        everyone may read from it.

        This type is useful for locally initializing some mutable data structure, then
        permanently freezing it to give read access to multiple threads. *)
    type 'a
         t :
         value
         mod contended forkable many portable unyielding
         with 'a portable @@ contended portable

    val to_repr : 'a t -> 'a portable Isolated.Repr.t
    val of_repr : 'a portable Isolated.Repr.t -> 'a t

    (** [create f] runs [f] within a fresh capsule, and creates a [Capsule.Frozen.t]
        containing the result. *)
    val create : (unit -> 'a @ portable) @ local once portable -> 'a t

    (** [unwrap t] takes a frozen capsule [t] and returns the underlying value at
        [shared]. *)
    val unwrap : 'a t -> 'a @ portable shared
  end

  module Owned : sig
    (** A capsule that uses [unique]ness tracking to enable different threads to gain
        [uncontended] access to its contents at different times without need for runtime
        synchronization. *)
    type 'a
         t :
         value
         mod contended forkable many portable unyielding
         with 'a @@ contended portable

    val to_repr : 'a t @ unique -> 'a Isolated.Repr.t @ unique
    val of_repr : 'a Isolated.Repr.t @ unique -> 'a t @ unique

    (** [create f] runs [f] within a fresh capsule, and creates a [Capsule.Owned.t]
        containing the result. *)
    val create : (unit -> 'a @ unique) @ local once portable -> 'a t @ unique

    (** [freeze t] takes an [aliased] owned capsule (which can no longer be written to
        since it isn't [unique]) and converts it to a {!Frozen.t}. *)
    val freeze : ('a : value mod portable). 'a t -> 'a Frozen.t

    (** [unwrap t] consumes a [unique] isolated capsule [t] and returns the underlying
        value, merging the capsule with the current capsule. *)
    val unwrap : 'a t @ unique -> 'a @ unique

    (** Project out a contended reference to the underlying value from a unique [t],
        returning the unique [t] back alongside the alias to the underlying value. *)
    val get_contended
      : ('a : value mod aliased portable).
      'a t @ unique -> #('a t * 'a) @ contended unique

    (** [with_ t ~f] takes a [unique] isolated capsule [t], calls [f] with its value, and
        returns a tuple of the unique isolated capsule and the result of [f]. *)
    val with_
      : ('a : value mod aliased) ('b : value mod contended portable).
      'a t @ unique
      -> f:('a -> 'b @ unique) @ local once portable
      -> #('a t * 'b) @ unique
  end

  module Scoped : sig
    type ('a, 'k) inner =
      #{ data : ('a, 'k) Data.t @@ global
       ; password : 'k Capsule.Password.t
       }

    (** An encapsulated value accessible for the duration of the current region.

        A value of type ['a Scoped.t] provides [uncontended] access to the underlying ['a]
        over a local scope. *)
    type 'a t = P : ('a, 'k) inner -> 'a t [@@unboxed]

    (** [with_ a ~f] calls [f] with a [local] {!Scoped.t} representing local access to
        [a], which lives in the current capsule. *)
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

          A value of type ['a Scoped.Shared.t] provides [shared] access to the underlying
          ['a] over a local scope. A [forkable] ['a Scoped.Shared.t] can be captured by
          functions that run from other capsules. *)
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
        (** Like ['a Scoped.Shared.t], but allows read-only computations to return an
            uncontended result in the current capsule. *)
        type ('a, 'k) t = ('a, 'k) inner =
          #{ data : ('a shared, 'k) Data.t @@ global
           ; password : 'k Capsule.Password.Shared.t
           }

        type ('a, 'b) f =
          { f : 'k. ('a, 'k) t @ forkable local -> ('b, 'k) Capsule.Data.Shared.t }

        (** [with_ a ~f] calls [f] with a [local forkable] {!Scoped.Shared.Uncontended.t}
            representing local read-only access to [a], which is readable in the current
            capsule.

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
    (** The initial capsule is the implicit capsule associated with the OCaml top level.
        Since this is the capsule in which library top-levels run, any [nonportable]
        top-level function belongs to the initial capsule, and hence is allowed to access
        it. *)

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
          [nonportable], requiring it to only be run from the initial capsule. *)
      val wrap : 'a @ l -> 'a t @ l

      (** Extract a value from a [Capsule.Data.t] for the initial capsule. This function
          is [nonportable], requiring it to only be run from the initial capsule. *)
      val unwrap : 'a t @ l -> 'a @ l]
    end
  end
end
