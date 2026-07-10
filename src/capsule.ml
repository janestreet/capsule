open! Base

(** Capsules

    Note that this module is reexported by [Core] *)

module Blocking_sync = Capsule_blocking_sync
module Prim = Capsule_prim
include Prim.Extended
