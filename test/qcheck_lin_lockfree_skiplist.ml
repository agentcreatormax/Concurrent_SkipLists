(** QCheck-Lin Linearizability Test for Lock-Free Skip List

    == Expected Result ==
    This test should PASS.
*)

open Lin

module LFS = Lockfree_skiplist

module LFSSig = struct
  type t = LFS.t

  let init ()   = LFS.create 8
  let cleanup _ = ()

  let int_small = nat_small
  let _ = (t, int_small)

  let api =
    [ val_ "add"      LFS.add      (t @-> int_small @-> returning bool)
    ; val_ "remove"   LFS.remove   (t @-> int_small @-> returning bool)
    ; val_ "contains" LFS.contains (t @-> int_small @-> returning bool)
    ]
end

module LFS_domain = Lin_domain.Make(LFSSig)

let () =
  QCheck_base_runner.run_tests_main [
    LFS_domain.lin_test ~count:1000
      ~name:"LockFree SkipList linearizability";
  ]