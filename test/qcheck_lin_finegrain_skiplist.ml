(** QCheck-Lin Linearizability Test for Fine-Grained Locking Skip List

    == Expected Result ==
    This test should PASS.
*)

open Lin

module FGS = Finegrain_skiplist

module FGSSig = struct
  type t = FGS.t

  let init ()   = FGS.create 8
  let cleanup _ = ()

  let int_small = nat_small
  let _ = (t, int_small)   (* suppress unused warnings *)

  let api =
    [ val_ "add"      FGS.add      (t @-> int_small @-> returning bool)
    ; val_ "remove"   FGS.remove   (t @-> int_small @-> returning bool)
    ; val_ "contains" FGS.contains (t @-> int_small @-> returning bool)
    ]
end

module FGS_domain = Lin_domain.Make(FGSSig)

let () =
  QCheck_base_runner.run_tests_main [
    FGS_domain.lin_test ~count:1000
      ~name:"FineGrain SkipList linearizability";
  ]