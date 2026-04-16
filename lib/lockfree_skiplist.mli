(** Lock-Free Skip List *)

(** The type of a lock-free skip list. *)
type t

val create : int -> t
(** [create max_level] creates an empty lock-free skip list with maximum level
    [max_level].
    @raise Invalid_argument if [max_level < 0] *)

val add : t -> int -> bool
(** [add s x] inserts key [x] into [s] if it is not already present.
    Returns [true] if [x] was added, and [false] if [x] was already present. *)

val remove : t -> int -> bool
(** [remove s x] removes key [x] from [s] if it is present.
    Returns [true] if [x] was removed, and [false] if [x] was not present. *)

val contains : t -> int -> bool
(** [contains s x] returns [true] if key [x] is present in [s],
    and [false] otherwise. *)