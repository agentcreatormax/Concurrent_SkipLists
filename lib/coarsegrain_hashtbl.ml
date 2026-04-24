type t = {
  mutex : Mutex.t;
  hashtbl : (int, unit) Hashtbl.t
}

let create lvl = 
  if lvl < 0 then invalid_arg "level must be > 0"
  else {
    mutex = Mutex.create ();
    hashtbl = Hashtbl.create (1 lsl lvl)
  }

let add tbl x =
  Mutex.lock tbl.mutex;
  if Hashtbl.mem tbl.hashtbl x then (
    Mutex.unlock tbl.mutex;
    false
  ) else (
    Hashtbl.add tbl.hashtbl x ();
    Mutex.unlock tbl.mutex;
    true
  )

let remove tbl x = 
  Mutex.lock tbl.mutex;
  if Hashtbl.mem tbl.hashtbl x then (
    Hashtbl.remove tbl.hashtbl x;
    Mutex.unlock tbl.mutex;
    true
  ) else (
    Mutex.unlock tbl.mutex;
    false
  )

let contains tbl x = 
  Mutex.lock tbl.mutex;
  let res = Hashtbl.mem tbl.hashtbl x in
  Mutex.unlock tbl.mutex;
  res