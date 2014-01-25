(**************************************)
(*                                    *)
(*  Proof tree with context variables *)
(*  (instead of real contexts)        *)
(*                                    *)
(*  Giselle Machado Reis              *)
(*  2013                              *)
(*                                    *)
(**************************************)

open Sequent
open Constraints
open Context
open ContextSchema
open Types
open Subexponentials
open Llrules

module type PROOFTREESCHEMA = 
  sig
  
    type prooftree = {
      conclusion : SequentSchema.sequent;
      mutable premises : prooftree list;
      mutable rule : llrule option 
    }
    val create : SequentSchema.sequent -> prooftree
    val getRule : prooftree -> Llrules.llrule option
    val copy : prooftree -> prooftree
    val appendLeaf : prooftree -> prooftree -> prooftree
    val getConclusion : prooftree -> SequentSchema.sequent
    val getOpenLeaves : prooftree -> SequentSchema.sequent list
    val decide : prooftree -> terms -> string -> prooftree * constraintset
    val releaseDown : prooftree -> prooftree * constraintset
    val releaseUp : prooftree -> terms -> prooftree * constraintset
    val applyWith : prooftree -> terms -> (prooftree * prooftree) * constraintset
    val applyParr : prooftree -> terms -> prooftree * constraintset
    val applyQst : prooftree -> terms -> prooftree * constraintset
    val applyForall : prooftree -> terms -> prooftree * constraintset
    val applyTop : prooftree -> unit
    val applyBot : prooftree -> terms -> prooftree * constraintset
    val applyOne : prooftree -> constraintset
    val applyInitial : prooftree -> terms -> constraintset list
    val applyAddOr1 : prooftree -> terms -> prooftree * constraintset
    val applyAddOr2 : prooftree -> terms -> prooftree * constraintset
    val applyExists : prooftree -> terms -> prooftree * constraintset
    val applyTensor : prooftree -> terms -> (prooftree * prooftree) * constraintset
    val applyBang : prooftree -> terms -> prooftree * constraintset
    val toTexString : prooftree -> string
    
  end
  
module ProofTreeSchema : PROOFTREESCHEMA = struct

  type prooftree = {
    conclusion : SequentSchema.sequent;
    mutable premises : prooftree list;
    mutable rule : llrule option
  }

  let create sq = {
    conclusion = sq;
    premises = [];
    rule = None
  }

  let getConclusion pt = pt.conclusion

  let getRule pt = pt.rule

  (* TODO: check if this actually copies a prooftree *)
  let rec copy pt = 
    let cp = create pt.conclusion in
    cp.rule <- pt.rule;
    let rec cpPremises lst = match lst with
      | [] -> []
      | p :: t -> (copy p) :: cpPremises t
    in
    cp.premises <- (cpPremises pt.premises);
    cp

  let rec getOpenLeaves pt = match pt.rule with
    | Some(r) -> List.flatten (List.map (fun p -> getOpenLeaves p) pt.premises)
    | None -> [pt.conclusion]

  let rec printOpenLeaves pt = match pt.rule with
    | Some(r) -> List.iter (fun p -> printOpenLeaves p) pt.premises
    | None -> print_endline( SequentSchema.toString pt.conclusion )

  (* Returns the sub-tree that has es as its end-sequent *)
  let rec getSubTree pt es = match (getConclusion pt) = es with
    | true -> [pt]
    | false -> List.concat (List.map (fun p -> getSubTree p es) pt.premises)

  (* If the end-sequent of leaf tree is the open sequent of pt, merge both proofs *)
  let appendLeaf pt leafTree = 
    let leaf = getConclusion leafTree in
    let open_leaves = getOpenLeaves pt in
    List.iter ( fun l ->
      if (l = leaf) then
	(* GR TODO improve this method. Maybe search only at the leaves?? *)
	match getSubTree pt leaf with
	| hd::tl -> hd.premises <- leafTree.premises; hd.rule <- leafTree.rule
	| [] -> failwith "Proof has no leaf matching the end-sequent of the sub-proof."
    ) open_leaves;
    pt

  (* Implement LL rules here! :) *)
  (* Each rule returns one or two proof trees and a constraintset, except if they
  have no premises (initial, top and one) *)

  (* About the decide rule:
     Currently, no constraints are being generated by the decide rule.
     Theoretically, we would need to check that the formula being decided on is
     actually in the context, but since our decides are done in a controlled way
     (we only decide on specification formulas that are in $infty, an unbounded
     context), these restrictions do not apply for our case and we don't create
     constraints.
  *)
  let decide pt f subexp = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    (* Create a new sequent and add this as a premise to the prooftree *)
    let premise = SequentSchema.createSync ctx f in
    let newpt = create premise in
    pt.rule <- Some(DECIDE);
    pt.premises <- [newpt];
    (newpt, Constraints.create []) 

  let releaseDown pt = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let goals = SequentSchema.getGoals conc in
    let newctx = ContextSchema.copy ctx in
    let premise = SequentSchema.createAsyn newctx goals in
    let newpt = create premise in
    pt.rule <- Some(RELEASEDOWN);
    pt.premises <- [newpt];
    (newpt, Constraints.create [])

  let releaseUp pt f = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let goals = SequentSchema.getGoals conc in
    let newctx = ContextSchema.insert ctx "$gamma" in
    let insertcstr = Constraints.insert f "$gamma" ctx newctx in
    let newgoals = List.filter (fun form -> form != f) goals in
    let premise = SequentSchema.createAsyn newctx newgoals in
    let newpt = create premise in
    pt.rule <- Some(RELEASEUP);
    pt.premises <- [newpt];
    (newpt, insertcstr)

  let applyWith pt f =
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let goals = SequentSchema.getGoals conc in
    let newctx1 = ContextSchema.copy ctx in
    let newctx2 = ContextSchema.copy ctx in
    let f1, f2 = match Term.observe f with 
      | WITH(f1, f2) -> f1, f2
      | _ -> failwith "Wrong formula in rule application."
    in
    let newgoals1 = f1 :: (List.filter (fun form -> form != f) goals) in
    let newgoals2 = f2 :: (List.filter (fun form -> form != f) goals) in
    let premise1 = SequentSchema.createAsyn newctx1 newgoals1 in
    let premise2 = SequentSchema.createAsyn newctx2 newgoals2 in
    let newpt1 = create premise1 in
    let newpt2 = create premise2 in
    pt.rule <- Some(WITHRULE);
    pt.premises <- [newpt1; newpt2];
    ((newpt1, newpt2), Constraints.create [])

  let applyParr pt f = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let goals = SequentSchema.getGoals conc in
    let newctx = ContextSchema.copy ctx in
    let f1, f2 = match Term.observe f with 
      | PARR(f1, f2) -> f1, f2 
      | _ -> failwith "Wrong formula in rule application."
    in
    let newgoals = f1 :: f2 :: (List.filter (fun form -> form != f) goals) in
    let premise = SequentSchema.createAsyn newctx newgoals in
    let newpt = create premise in
    pt.rule <- Some(PARRRULE);
    pt.premises <- [newpt];
    (newpt, Constraints.create [])

  let applyQst pt f =
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let goals = SequentSchema.getGoals conc in
    let subexp, f1 = match Term.observe f with 
      | QST(CONST(s), f1) -> s, f1
      | _ -> failwith "Wrong formula in rule application."
    in
    let newctx = ContextSchema.insert ctx subexp in
    let insertcstr = Constraints.insert f1 subexp ctx newctx in
    let newgoals = List.filter (fun form -> form != f) goals in
    let premise = SequentSchema.createAsyn newctx newgoals in
    let newpt = create premise in
    pt.rule <- Some(QSTRULE);
    pt.premises <- [newpt];
    (newpt, insertcstr)

  let applyForall pt f = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let goals = SequentSchema.getGoals conc in
    let s, i, f1 = match Term.observe f with
      | FORALL(s, i, f1) -> s, i, f1
      | _ -> failwith "Wrong formula in rule application."
    in
    let newctx = ContextSchema.copy ctx in
    Term.varid := !Term.varid + 1;
    let new_var = VAR ({str = s; id = !Term.varid; tag = EIG; ts = 0; lts = 0}) in
    let newf = Norm.hnorm (APP (ABS (s, 1, f1), [new_var])) in
    let newgoals = newf :: (List.filter (fun form -> form != f) goals) in
    let premise = SequentSchema.createAsyn newctx newgoals in
    let newpt = create premise in
    pt.rule <- Some(FORALLRULE);
    pt.premises <- [newpt];
    (newpt, Constraints.create [])

  (* GR: Do we need to create any constraints for the T rule? *)
  let applyTop pt = pt.rule <- Some(TOPRULE)

  let applyBot pt f = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let goals = SequentSchema.getGoals conc in
    let newctx = ContextSchema.copy ctx in
    let newgoals = List.filter (fun form -> form != f) goals in
    let premise = SequentSchema.createAsyn newctx newgoals in
    let newpt = create premise in
    pt.rule <- Some(BOTRULE);
    pt.premises <- [newpt];
    (newpt, Constraints.create [])

  (* GR TODO assert that the main formulas are the only ones in the goals of
  synchronous phase?? *)

  let applyOne pt =
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    pt.rule <- Some(ONERULE);
    Constraints.empty "$gamma" ctx

  (* About the initial rule:
     The initial rule generates constraints of the type ":- not in(F, G1).",
     which means that the proof fails if the formula F is not in the context G.
     This, combined with the end-sequent constraints ("in(F, G0)") guarantee
     that correct derivations will be generated, and only when the formula is
     available.
  *)
  let applyInitial pt f = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let initcstr = Constraints.initial ctx f in
    pt.rule <- Some(INIT);
    initcstr

  let applyAddOr1 pt f = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let newctx = ContextSchema.copy ctx in
    let f1 = match Term.observe f with
      | ADDOR(f1,_) -> f1
      | _ -> failwith "Wrong formula in rule application."
    in
    let premise = SequentSchema.createSync newctx f1 in
    let newpt = create premise in
    pt.rule <- Some(ADDOR1RULE);
    pt.premises <- [newpt];
    (newpt, Constraints.create [])

  let applyAddOr2 pt f = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let newctx = ContextSchema.copy ctx in
    let f2 = match Term.observe f with
      | ADDOR(_,f2) -> f2
      | _ -> failwith "Wrong formula in rule application."
    in
    let premise = SequentSchema.createSync newctx f2 in
    let newpt = create premise in
    pt.rule <- Some(ADDOR2RULE);
    pt.premises <- [newpt];
    (newpt, Constraints.create [])

  let applyExists pt f = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let s, i, f1 = match Term.observe f with
      | EXISTS(s, i, f1) -> s, i, f1
      | _ -> failwith "Wrong formula in rule application."
    in
    let newctx = ContextSchema.copy ctx in
    Term.varid := !Term.varid + 1;
    let new_var = V ({str = s; id = !Term.varid; tag = CST; ts = 0; lts = 0}) in
    let ptr = PTR {contents = new_var} in
    let newf = Norm.hnorm (APP (ABS (s, 1, f1), [ptr])) in
    let premise = SequentSchema.createSync newctx newf in
    let newpt = create premise in
    pt.rule <- Some(EXISTSRULE);
    pt.premises <- [newpt];
    (newpt, Constraints.create [])

  let applyTensor pt f = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let f1, f2 = match Term.observe f with
      | TENSOR(f1, f2) -> f1, f2
      | _ -> failwith "Wrong formula in rule application."
    in
    let (newctx1, newctx2) = ContextSchema.split ctx in
    let splitcstr = Constraints.split ctx newctx1 newctx2 in
    let premise1 = SequentSchema.createSync newctx1 f1 in
    let premise2 = SequentSchema.createSync newctx2 f2 in
    let newpt1 = create premise1 in
    let newpt2 = create premise2 in
    pt.rule <- Some(TENSORRULE);
    pt.premises <- [newpt1; newpt2];
    ((newpt1, newpt2), splitcstr)

  let applyBang pt f = 
    let conc = getConclusion pt in
    let ctx = SequentSchema.getContext conc in
    let s, f1 = match Term.observe f with
      | BANG(CONST(s), f1) -> s, f1
      | _ -> failwith "Wrong formula in rule application."
    in
    let newctx = ContextSchema.bang ctx s in
    let bangcstr = Constraints.bang newctx s in
    let premise = SequentSchema.createAsyn newctx [f1] in
    let newpt = create premise in
    pt.rule <- Some(BANGRULE);
    pt.premises <- [newpt];
    (newpt, bangcstr)


  let rec toTexString pt = match pt.rule with
    | Some(r) ->
      let topproof = match pt.premises with
        | [] -> ""
        | hd::tl -> (toTexString hd)^(List.fold_right (fun el acc -> (*"\n&\n"^*)(toTexString el)) tl "") 
      in
      (*"\\infer{"^(SequentSchema.toTexString (getConclusion pt))^"}\n{"^topproof^"}"*)
      "\\cfrac{"^topproof^"}\n{"^(SequentSchema.toTexString (getConclusion pt))^"}"
    | None -> (SequentSchema.toTexString (getConclusion pt))

end
;;

