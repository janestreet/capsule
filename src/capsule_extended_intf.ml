open! Base

(** For now, see the {!Capsule_expert} library for high-level documentation of capsule
    types.

    This module provides an interface to capsules that is a small subset of
    [Capsule_expert], starting with the most common entry points. The interface is also
    cleaned up to be somewhat easier to use, and more consistent with other conventions in
    [Base].

    Over time we will provide more of [Capsule_expert]'s functionality. *)
module type Capsule = sig
  module Capsule := Capsule_expert

  module Access : sig
    type 'k t = 'k Capsule.Access.t
    type packed = Capsule.Access.packed = P : 'k t -> packed [@@unboxed]
    type 'k boxed = 'k Capsule.Access.boxed

    (** Obtain an [Access.t] for the current capsule. Since we do not know the brand for
        the current capsule, we receive a fresh one. *)
    val current : unit -> packed

    val unbox : 'k boxed -> 'k t
    val box : 'k t -> 'k boxed
  end

  module Data : sig
    type ('a, 'k) t = ('a, 'k) Capsule.Data.t

    (** These functions are the most common way to interact with capsules. *)

    val%template create : (unit -> 'a) -> ('a, 'k) t [@@mode u = (unique, aliased)]

    [%%template:
    [@@@mode.default l = (global, local)]

    val wrap : access:'k Access.t -> 'a -> ('a, 'k) t

    val unwrap : 'a 'k. access:'k Access.t -> ('a, 'k) t -> 'a
    [@@mode l = l, (c, p) = ((uncontended, nonportable), (shared, portable))]

    (** These functions enable more complicated manipulation of capsules. *)

    val return : 'a -> ('a, 'k) t
    val both : ('a, 'k) t -> ('b, 'k) t -> ('a * 'b, 'k) t
    val fst : ('a * _, 'k) t -> ('a, 'k) t
    val snd : (_ * 'b, 'k) t -> ('b, 'k) t

    (** Retrieve the value in a capsule directly. Likely only useful if the capsule has
        already been [map]'d, as capsules do not usually contain portable values. *)
    val get_id : 'a 'k. ('a, 'k) t -> 'a]
  end

  module Isolated : sig
    (** The underlying representation of both [Frozen.t] and [Owned.t]. *)
    module Repr : sig
      type ('a, 'k) inner =
        { data : ('a, 'k) Data.t
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
    type 'a t

    val to_repr : 'a t -> 'a portable Isolated.Repr.t
    val of_repr : 'a portable Isolated.Repr.t -> 'a t

    (** [create f] runs [f] within a fresh capsule, and creates a [Capsule.Frozen.t]
        containing the result. *)
    val create : (unit -> 'a) -> 'a t

    (** [unwrap t] takes a frozen capsule [t] and returns the underlying value at
        [shared]. *)
    val unwrap : 'a t -> 'a
  end

  module Owned : sig
    (** A capsule that uses [unique]ness tracking to enable different threads to gain
        [uncontended] access to its contents at different times without need for runtime
        synchronization. *)
    type 'a t

    val to_repr : 'a t -> 'a Isolated.Repr.t
    val of_repr : 'a Isolated.Repr.t -> 'a t

    (** [create f] runs [f] within a fresh capsule, and creates a [Capsule.Owned.t]
        containing the result. *)
    val create : (unit -> 'a) -> 'a t

    (** [freeze t] takes an [aliased] owned capsule (which can no longer be written to
        since it isn't [unique]) and converts it to a {!Frozen.t}. *)
    val freeze : 'a. 'a t -> 'a Frozen.t

    (** [unwrap t] consumes a [unique] isolated capsule [t] and returns the underlying
        value, merging the capsule with the current capsule. *)
    val unwrap : 'a t -> 'a

    (** Project out a contended reference to the underlying value from a unique [t],
        returning the unique [t] back alongside the alias to the underlying value. *)
    val get_contended : 'a. 'a t -> 'a t * 'a

    (** [with_ t ~f] takes a [unique] isolated capsule [t], calls [f] with its value, and
        returns a tuple of the unique isolated capsule and the result of [f]. *)
    val with_ : 'a 'b. 'a t -> f:('a -> 'b) -> 'a t * 'b
  end

  module Scoped : sig
    type ('a, 'k) inner =
      { data : ('a, 'k) Data.t
      ; password : 'k Capsule.Password.t
      }

    (** An encapsulated value accessible for the duration of the current region.

        A value of type ['a Scoped.t] provides [uncontended] access to the underlying ['a]
        over a local scope. *)
    type 'a t = P : ('a, 'k) inner -> 'a t [@@unboxed]

    (** [with_ a ~f] calls [f] with a [local] {!Scoped.t} representing local access to
        [a], which lives in the current capsule. *)
    val with_ : 'a -> f:('a t -> 'b) -> 'b

    (** [get t ~f] computes a value using the data accessible via [t]. *)
    val get : 'a t -> f:('a -> 'b) -> 'b

    (** Like [get], but for for functions that return [unit]. *)
    val iter : 'a t -> f:('a -> unit) -> unit

    (** Construct a new [t] by mapping a function over the referenced value. *)
    val map : 'a t -> f:('a -> 'b) -> 'b t

    module Shared : sig
      type ('a, 'k) inner =
        { data : ('a shared, 'k) Data.t
        ; password : 'k Capsule.Password.Shared.t
        }

      (** An encapsulated value that may be read for the duration of the current region.

          A value of type ['a Scoped.Shared.t] provides [shared] access to the underlying
          ['a] over a local scope. A [forkable] ['a Scoped.Shared.t] can be captured by
          functions that run from other capsules. *)
      type 'a t = P : ('a, 'k) inner -> 'a t [@@unboxed]

      (** [with_ a ~f] calls [f] with a [local forkable] {!Shared.t} representing local
          read-only access to [a], which is readable in the current capsule. *)
      val with_ : 'a 'b. 'a -> f:('a t -> 'b) -> 'b

      (** [get t ~f] computes a value using data accessible via [t]. *)
      val get : 'a 'b. 'a t -> f:('a -> 'b) -> 'b

      (** Like [get], but for for functions that return [unit]. *)
      val iter : 'a. 'a t -> f:('a -> unit) -> unit

      (** Construct a new [t] by mapping a function over the referenced value. *)
      val map : 'a 'b. 'a t -> f:('a -> 'b) -> 'b t

      module Uncontended : sig
        (** Like ['a Scoped.Shared.t], but allows read-only computations to return an
            uncontended result in the current capsule. *)
        type ('a, 'k) t = ('a, 'k) inner =
          { data : ('a shared, 'k) Data.t
          ; password : 'k Capsule.Password.Shared.t
          }

        type ('a, 'b) f = { f : 'k. ('a, 'k) t -> ('b, 'k) Capsule.Data.Shared.t }

        (** [with_ a ~f] calls [f] with a [local forkable] {!Scoped.Shared.Uncontended.t}
            representing local read-only access to [a], which is readable in the current
            capsule.

            The result of [f] is a [Capsule.Data.Shared.t], which can be unwrapped in the
            current capsule. *)
        val with_ : 'a -> ('a, 'b) f -> 'b

        (** [get t ~f] computes a value using data accessible via [t]. *)
        val get : 'a 'b 'k. ('a, 'k) t -> f:('a -> 'b) -> ('b, 'k) Capsule.Data.Shared.t

        (** Construct a new [t] by mapping a function over the referenced value. *)
        val map : 'a 'b 'k. ('a, 'k) t -> f:('a -> 'b) -> ('b, 'k) t
      end
    end
  end

  module Initial : sig
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
      val wrap : 'a -> 'a t

      (** Extract a value from a [Capsule.Data.t] for the initial capsule. This function
          is [nonportable], requiring it to only be run from the initial capsule. *)
      val unwrap : 'a t -> 'a]
    end
  end
end
