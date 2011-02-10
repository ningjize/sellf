open Term
open Structs
open Unify

let unify = 
  let module Unify = 
    Unify.Make ( struct
      let instantiatable = Term.LOG
      let constant_like = Term.EIG
    end )
  in Unify.pattern_unify

(* Solves an arithmetic expression *)
let rec solve_exp e = match e with
  | INT (x) -> x
  | VAR v -> 1(* Infer the variable value?? *)
  | PLUS (x, y) -> (solve_exp x) + (solve_exp y)
  | MINUS (x, y) -> (solve_exp x) - (solve_exp y)
  | TIMES (x, y) -> (solve_exp x) * (solve_exp y)
  | DIV (x, y) -> (solve_exp x) / (solve_exp y)
  | PTR {contents = T t} -> solve_exp t
  | PTR {contents = V t} when t.tag = Term.LOG -> 
      print_string "ERROR: Cannot handle comparisons with logical variables.";  print_term e; print_newline (); 0
  | bla -> print_string "[ERROR] Unexpected term in a comparison: "; print_term bla; print_newline (); 0
;;

let unbounded s = let subexps = keys subexTpTbl in
  let rec get_unbounded lst = match lst with
    | [] -> ()
    | u :: t -> (match Hashtbl.find subexTpTbl s with
      | UNB -> Hashtbl.add subexOrdTbl s u; (get_unbounded t)
      | _ -> get_unbounded t
    )
  in get_unbounded subexps
;;

(* Creating a new subexponential *)
(* TODO: s -> holds all unbounded subexponentials *)
let new_subexp s = 
  try match Hashtbl.find subexTpTbl s with
  | _ -> ()
  with Not_found -> Hashtbl.add subexTpTbl s (LIN); Hashtbl.add !context s []; unbounded s ;;

(* Verifying if a subexponential is empty *)
let empty s = List.length (Hashtbl.find !context s) == 0 ;;

(* Checks if a subexponential s1 > s2 *)

let rec bfs root queue goal = match queue with
  | [] -> false
  | h :: t when h = root -> failwith "Circular dependency on subexponential order."
  | h :: t when h = goal -> true
  | h :: t -> bfs root (t @ Hashtbl.find_all subexOrdTbl h) goal
;;

let greater_than s1 s2 = bfs s2 (Hashtbl.find_all subexOrdTbl s2) s1 ;;

(* END Checks if a subexponential s1 > s2 *)

(* Checks if bang rule can be applied with subexponential s *)
let rec cb s idxs = match idxs with
  | [] -> true
  | i::t  -> 
    if i == "$gamma" then cb s t
    else
      try match Hashtbl.find subexTpTbl i with
        | UNB | AFF -> cb s t (* This can suffer weakening, go on... *)
        | REL | LIN -> (try match Hashtbl.find !context i with
          | [] -> cb s t
          | _ -> if i = s || (greater_than i s) then cb s t (* This subexp can have formulas in it. *)
                 else (print_string ("Failed in bang rule: "^i^"  "^s^"\n"); false)
          with Not_found -> cb s t ) (* This means that this subexp is empty *)
      with Not_found -> print_string ("[ERROR] Subexponential "^i^" has no type defined."); false
;;

let condition_bang s = let idxs = keys !context in cb s idxs;;

(* Removes all formulas from a subexponential *)
let remove_all s = Hashtbl.remove !context s; Hashtbl.add !context s [] ;;

(* Operation k <l for K context *)
let k_less_than s = Hashtbl.iter (fun idx forms -> if idx != "$gamma" && not (idx = s) && not (greater_than idx s) then begin print_string ("Removing from "^idx^" in k_less_than "^s^"\n"); remove_all idx end) !context;;

(* Checks whether or not a subexponential can suffer weakening *)
let weak i = try match Hashtbl.find subexTpTbl i with
  | UNB | AFF -> true
  | REL | LIN -> false
  with Not_found -> print_string ("[ERROR] Subexponential "^i^" has no type defined."); false

(* Returns a list with all the formulas that cannot suffer weakening *)
(* FIXME: this dummy parameter was used so the method was called... *)
let weakenable dummy = Hashtbl.fold (fun s forms l -> 
    (*print_string s;
    print_list_terms forms;*)
    if not (weak s) then 
    begin
      forms@l
    end
    else l) !context [] ;;

(* Checks whether K context is empty on the subexponentials that cannot suffer weakening *)
(* FIXME: this dummy parameter was used so the method was called... *)
let empty_nw dummy =
  match (List.length (weakenable ())) with
    | 0 -> print_string "Weakenable subexponential"; true
    | n -> print_string "Non-weakenable context is not empty.\n"; 
    if !is_top then (print_string "However, the proof has a top.\n"; true) else false
;;

(* Saves the state for backtracking later (called whenever a non-deterministic
 * choice is made, i.e., when a positive formula or atom is focused on) *)
let save_state form tp pos bind suc fail bck_clauses =  
  let ctx_cp = Hashtbl.copy !context in
  let cls_cp = Hashtbl.copy !clausesTbl in
  let dt = DATA(!goals, !positives, !atoms, ctx_cp, cls_cp, !is_top) in
  (*let st = STATE(dt, form, tp, pos, !bind_len, !branch, suc, fail, bck_clauses) in*)
  let st = STATE(dt, form, tp, pos, bind, !branch, suc, fail, bck_clauses) in
  nstates := !nstates + 1;
  print_string "+++++ Saving formula "; print_term form; print_string " on state stack as ";
  print_formType tp; print_newline ();
  (*print_hashtbl !context;*)
  Stack.push st !states;
  print_stack !states
;;

let reset dt = match dt with
  | DATA (g, p, a, c, ct, isT) ->
    goals := g;
    positives := p;
    atoms := a;
    context := Hashtbl.copy c;
    clausesTbl := Hashtbl.copy ct;
    is_top := isT
;;

(* Functions to substitute a variable in a formula *)
let rec apply_ptr f = match f with
  | ABS(s, i, t) ->
      varid := !varid + 1;
      let newVar = V {str = s; id = !varid; tag = Term.LOG; ts = 0; lts = 0} in
      let ptr = PTR {contents = newVar} in
      (*print_string "\nApplying "; print_term ptr; print_string " to "; print_term (ABS(s, i, t)); print_newline ();*)
      let newf = Norm.hnorm (APP(ABS(s, i, t), [ptr])) in
      apply_ptr newf
  | x -> x

(* [END] Functions to transform variables to pointers in a formula *)

let unifies f1 f2 =
  let fp1 = apply_ptr f1 in
  let fp2 = apply_ptr f2 in
    print_string "****** Unifying (head of first with second): \n"; print_term fp1; print_newline (); print_term fp2;
    print_newline ();
    match fp1, fp2 with
    | LOLLI(CONS(s), head, body), (PRED (str2, terms2)) -> 
      begin match head with
      | (PRED(str1, terms1)) ->
        begin try match unify terms1 terms2 with
          | () ->
            print_string "******* After unification: \n"; print_term fp1; print_newline ();
            print_term fp2; print_newline ();
            (fp1, fp2)
          with _ ->  failwith "Unification not possible."
        end
      | _ -> failwith "Head of a clause not a predicate."
      end
    | _ -> failwith "Formulas not compatible (should be lolli and pred)."
;;

(* Solves an arithmetic comparison *)
let solve_cmp c e1 e2 = 
  let n1 = solve_exp e1 in 
  let n2 = solve_exp e2 in
    match c with
      | EQ -> n1 = n2
      | LESS -> n1 < n2
      | GEQ -> n1 >= n2        
      | GRT -> n1 > n2
      | LEQ -> n1 <= n2
      | NEQ -> n1 != n2
;;

(*Solves assignment *)
let solve_asgn e1 e2 = 
  print_string "****** Unifying (head of first with second): \n"; print_term e1; print_newline (); print_term e2;
  print_newline ();
  let n2 = solve_exp e2 in
  try 
    unify e1 (INT(n2)); 
    print_string "******* After unification: \n"; print_term e1; print_newline ();
    print_int n2; print_newline ();
    true
  with 
  | _ -> print_endline "Failed to assign a variable to an int in an assigment."; false;;

(* Solves a LL formula *)

(* Classic version *) (* Change this. solve is no longer returning true or false *)
let rec solve suc fail = solve_neg suc fail

and solve_neg suc fail = (*match !goals with*)
try
let form = List.hd !goals in
let t = List.tl !goals in
match Term.observe form with

  (* Negative formulas *)

  (* Put f1 in subexponential s of the context, put (f1, s) in head f1 of clausesTbl and continue with f2 *)
  (* If s is $gamma (linear implication), decompose f1 up to negatives and atoms and put these formulas in $gamma *)
  (* Otherwise, put f1 in subexponential s and f1 :- f2 in the clauses hash 
  (Note that f1 is either an atom or -o if it's in a subexponential.) *)
  | LOLLI (sub, f1, f2) -> (match (Term.observe sub) with
    | CONS("$gamma") -> 
      let terminate = ref true in
      let rec decompose f = match f with
        | TENSOR (form1, form2) -> decompose form1; decompose form2
        | BANG (s, form) | HBANG (s, form) -> ( match form, (Term.observe s) with
          | PRED(str,terms), CONS(sub) -> 
            add_ctx (LOLLI (CONS(sub), PRED(str,terms), ONE)) sub;
            add_cls (LOLLI (CONS(sub), PRED(str,terms), ONE))
          | LOLLI(CONS(se), fl1, fl2), CONS(sub) ->
            add_ctx (LOLLI(CONS(se), fl1, fl2)) se;
            add_cls (LOLLI(CONS(se), fl1, fl2))
          | _ -> failwith "Lolli head error or unitialized subexponential"
        )
        | PRED (str, terms) ->
          add_lin (LOLLI (CONS("$gamma"), PRED(str,terms), ONE));
          add_cls (LOLLI (CONS("$gamma"), PRED(str,terms), ONE))
        | COMP(ct, t1, t2) -> if solve_cmp ct t1 t2 then () 
          else terminate := true
        | ASGN( t1, t2) -> if solve_asgn t1 t2 then () 
          else terminate := true
        | PRINT(t1) -> print_endline ""; print_term t1; print_endline ""
        | x -> add_lin x (* Negative formula or atom *)
      in decompose f2; goals := (f1 :: t); if !terminate then suc () else solve_neg suc fail
    | CONS(subexp) -> ( match f2 with
      (* TODO: Should I check the cases for equalities here also? What about the rest of the cases? *)
      | PRED(str,terms) ->
        add_ctx (LOLLI (CONS(subexp), PRED(str,terms), ONE)) subexp;
        add_cls (LOLLI (CONS(subexp), PRED(str,terms), ONE));
        goals := (f1 :: t); solve_neg suc fail
      | LOLLI(sub2, fl1, fl2) ->
        begin match sub2 with
          | CONS(se) ->
            add_ctx (LOLLI(CONS(se), fl1, fl2)) se;
            add_cls (LOLLI(CONS(se), fl1, fl2)); 
            goals := (f1 :: t); solve_neg suc fail
          | _ -> failwith "Unitialized subexponential while solving negative formulas."
        end
      | _ -> failwith "Lolli head error"
    )
  )
  (* Solves f1 and f2 with the same context *)
  | WITH (f1, f2) -> (
    (*let st = !nstates in*)
    let orig_context = !context in
    let orig_states = !states in
    let orig_clauses = !clausesTbl in
    add_goals f1; 
    solve_neg (fun () -> 
      context := orig_context;
      states := orig_states;
      clausesTbl := orig_clauses;
      add_goals f2; 
      solve_neg suc fail) fail
    (*let orig_context = !context in
    let orig_states = !states in
    let orig_clauses = !clausesTbl in
    goals := (f1 :: t);
    if solve_neg () then 
    (
      context := orig_context;
      states := orig_states;
      clausesTbl := orig_clauses;
      goals := (f2 :: t);
      solve_neg ()
    )
    else false*)
  )
  | FORALL (s, i, f) ->
      varid := !varid + 1;
      let new_var = VAR ({str = s; id = !varid; tag = Term.EIG; ts = 0; lts = 0}) in
      (*let newf = subst_var new_var f in*)
      let newf = Norm.hnorm (APP (ABS (s, 1, f), [new_var])) in
      goals := newf :: t;
      solve_neg suc fail
  
  | TOP -> is_top := true; suc () (* This is in fact not correct. We have to mark the formulas in the context that can be weakened. *)

  | NEW (s, t1) -> 
      varid := !varid + 1;
      let string_sub = "NSUBEXP"^(string_of_int !varid) in
      let new_cons = CONS string_sub in
      let newf = Norm.hnorm (APP (ABS (s, 1, t1), [new_cons])) in
      new_subexp string_sub;
      goals := newf :: t;
      solve_neg suc fail

  (* Positive formulas *)

  | TENSOR (f1, f2) -> add_pos (TENSOR (f1, f2)); goals := t; solve_neg suc fail
  | BANG (s, f) -> add_pos (BANG (s, f)); goals := t; solve_neg suc fail
  | HBANG (s, f) -> add_pos (HBANG (s, f)); goals := t; solve_neg suc fail
  | ONE -> add_pos ONE; goals := t; solve_neg suc fail
  | COMP (ct, t1, t2) -> add_pos (COMP (ct, t1, t2)); goals := t; solve_neg suc fail
  | ASGN (t1, t2) -> add_pos (ASGN (t1, t2)); goals := t; solve_neg suc fail
  | PRINT (t1) -> add_pos (PRINT (t1)); goals := t; solve_neg suc fail

  (* Atoms *)
  | PRED(str, terms) -> add_atm (PRED(str, terms)); goals := t; solve_neg suc fail

  | EQU (str, n, trm) -> print_string "Not solving term equality yet."; fail ()
  | CUT -> print_string "What should I do when encounter a cut?"; fail ()
  | CONS(str) -> add_atm (PRED (str, CONS(str))); goals := t; solve_neg suc fail
  | APP(head, arg1) -> 
    begin
      match (Norm.hnorm (APP( (Term.observe head), arg1))) with
      | f -> (match f with 
        | CONS(str) -> add_atm (PRED (str, CONS(str))); goals := t; solve_neg suc fail
        | APP(CONS(str3), arg2) -> add_atm (PRED (str3, APP(CONS(str3), arg2))); 
          goals := t; solve_neg suc fail
        )
    end

  | h -> print_term h; failwith " Solving not implemented for this case."

  (* Empty list, solve the positive formulas now *)
    
  with 
    | Failure "hd" -> solve_pos suc fail


and solve_pos suc fail = (*match !positives with*)
try
let form = List.hd !positives in
let t = List.tl !positives in
match Term.observe form with

  (* If a negative formulas was found, put it in goals list and call solve again (back to async phase) *)
     
  | LOLLI (sub, f1, f2) -> 
    begin 
      match Term.observe sub with
      | CONS(s) -> 
        add_goals (LOLLI (sub, f1, f2)); 
        solve_neg (fun () -> solve_pos suc fail) fail (* G: I think I can replace this with 'solve suc fail' *)
      | _ -> failwith "Unitialized subexponential while solving postive formulas."
   end

  | WITH (f1, f2) -> 
    add_goals (WITH (f1, f2));
    solve_neg (fun () -> solve_pos suc fail) fail
   
  | FORALL (s, i, f) -> 
    add_goals (FORALL (s, i, f));
    solve_neg (fun () -> solve_pos suc fail) fail
    
  | TOP -> 
    add_goals TOP;
    solve_neg (fun () -> solve_pos suc fail) fail
   
  | NEW (s,t1) -> 
    add_goals (NEW (s,t1));
    solve_neg (fun () -> solve_pos suc fail) fail
    
  (* Positive formulas *)

  | TENSOR (f1, f2) ->
    add_goals f1;
    positives := t;
    solve (fun () -> add_goals f2; 
                     let st = !nstates in 
                     solve suc (fun () -> print_string "Linha 340\n"; restore_atom st)) fail

  | BANG (sub, f) -> 
    begin (*print_string "Context before applying bang rule: \n"; print_hashtbl !context; print_newline ();*)
      match Term.observe sub with
      | CONS(s) -> 
          if condition_bang s then begin
          (*print_string "Context before k_less_than: \n"; print_hashtbl !context; print_newline ();*)
          k_less_than s; 
          (*print_string "Context after k_less_than: \n"; print_hashtbl !context; print_newline ();*)
          positives := t;
          add_goals f;
          solve suc fail
          (* I will not save the state here. If f is proved, I would have to make
            positives := []; save_state ...; solve_pos ()
            which would yield true anyway
          *)
        end
        else fail ()
      | _ -> failwith "Not expected subexponential while solving positive formulas."
    end

  | HBANG (sub, f) -> begin
    match Term.observe sub with
      | CONS (s) -> ( try match Hashtbl.find !context s with
        | [] -> print_string "Solved hbang.\n"; positives := t; add_goals f; solve suc fail 
        | _ -> print_string "Failed in hbang rule\n"; fail ()
        with Not_found -> print_string "Solved hbang.\n"; positives := t; add_goals f; solve suc fail
      )
      | _ -> failwith "Not expected subexponential while solving positive formulas."
    end

  | ONE -> positives := t; suc () 
    (* If I am solving a tensor, I can leave the checking of empty context for the next formula. *)
    (*if empty_nw () then begin
      positives := t;
      if (List.length !positives) != 0 then
        save_state (List.hd !positives) POS 0 suc fail;
      solve_pos suc fail
    end    
    else fail ()*)

  | COMP (ct, t1, t2) -> 
    if (solve_cmp ct t1 t2) then begin
      positives := t;
      if (List.length !positives) != 0 then
        save_state (List.hd !positives) POS 0 !bind_len suc fail [];
      solve_pos suc fail
    end    
    else fail ()

  | ASGN (t1, t2) -> 
      if (solve_asgn t1 t2) then begin
        positives := t;
        if (List.length !positives) != 0 then
          save_state (List.hd !positives) POS 0 !bind_len suc fail [];
        solve_pos suc fail
      end    
      else fail ()

  | PRINT (t1) -> print_endline ""; print_term t1; print_endline "";
       positives := t;
        if (List.length !positives) != 0 then
          save_state (List.hd !positives) POS 0 !bind_len suc fail [];
        solve_pos suc fail

  (* Atoms *)
  | PRED (str, terms) -> add_atm (PRED (str, terms)); positives := t; solve_pos suc fail

  | EQU (str, n, trm) -> print_string "Not solving term equality yet."; fail ()
  | CUT -> print_string "What should I do when encounter a cut?"; fail ()
  | CONS(str) -> add_atm (PRED (str, CONS(str))); positives := t; solve_pos suc fail
  | APP(head, arg1) -> 
    begin
      match (Norm.hnorm (APP(head, arg1))) with
      | CONS(str) -> add_atm (PRED (str, CONS(str))); positives := t; solve_pos suc fail
      | APP(CONS(str3), arg2) -> add_atm (PRED (str3, APP(CONS(str3), arg2))); 
          positives := t; solve_pos suc fail
    end
  
  | h -> print_term h; failwith " Solving not implemented for this case."

  (* Empty list, solve the atoms now *)

  (*| [] -> true*)
  with 
    | Failure "hd" -> solve_atm suc fail

and solve_atm_aux suc fail forms =
(*try*) (*No need for the try anymore. We are sure that there is a goal.*)
let form = List.hd !atoms in
let t = List.tl !atoms in
match Term.observe form with
  | PRED (str, terms) -> (
    try match forms with
      | lolli :: t1 -> (
        try match unifies lolli (PRED(str, terms)) with
          | (LOLLI(CONS(s), fp1, fp2), f_ptr) -> (
            print_endline "Creating a new entry in the stack without deleting.";
            (try match Hashtbl.find subexTpTbl s with
              | LIN | AFF -> ( rmv_ctx lolli s; rmv_cls lolli )
              | REL | UNB -> () 
              with Not_found -> print_string ("This subexponential has no type: "^s); print_newline (); fail ()
            );
            let st = !nstates in
            atoms := t;
            add_goals fp2;
              (*solve suc (fun () -> print_string "Fail 435\n"; restore st)*)
            solve suc fail
          )
          | (a, b) -> print_term a; print_string " and "; print_term b; print_newline ();
            failwith "Unexpected return from unifies"
          with 
            | Failure "Unification not possible." ->  fail ()
            | Failure "Head of a clause not a predicate." -> fail ()
            | Failure "Formulas not compatible (should be lolli and pred)." -> fail ()
            | Failure str -> failwith str
          )
          (*| _ :: t -> failwith "Not a lolli in clauses' table"*)
      | [] -> print_string ("No clauses for this atom: "^str^".\n"); print_string "Backtracking...\n"; fail ()
        (*in attempt clauses (PRED (str, terms))*)
      with Not_found -> print_string "[ERROR] Atom not in table: "; print_string str; fail ()
  )
  | bla -> failwith "\nNot an atom in atoms' list"
(*  with 
    | Failure "hd" -> print_string "Strange failure"; print_endline ""; suc ()*)



and solve_atm suc fail = (*trying to prove an atom and needing to initialize the stack*)
try
let form = List.hd !atoms in
let t = List.tl !atoms in
match Term.observe form with
  | PRED (str, terms) -> (
    try 
      begin
        match Hashtbl.find !clausesTbl str with
        | lolli :: t1 -> 
          let bind_b4 = !bind_len in (*We need to get the binding of substitutions used until this point, not after the next unification.*)
          atoms := form :: t;
          save_state (PRED(str, terms)) BODY 0 bind_b4 suc fail t1;
          let st = !nstates in
          solve_atm_aux suc (fun () -> print_endline "Fail: 435"; restore_atom st) (lolli :: t1)
        | [] -> print_string ("No clauses for this atom: "^str^".\n"); print_string "Backtracking...\n"; fail ()
      end
        (*in attempt clauses (PRED (str, terms))*)
       with Not_found -> print_string "[ERROR] Atom not in table: "; print_string str; fail ()
    )
  | bla -> failwith "\nNot an atom in atoms' list"
  with 
    | Failure "hd" -> (*print_string "Strange failure"; print_endline "";*) suc ()

and back_chain forms suc fail = (*already initialized the stack, but now we need to backtrack using another clause in the context.*)
try
let form = List.hd !atoms in
let t = List.tl !atoms in
match Term.observe form with
  | PRED (str, terms) -> (
    try 
      begin
        match forms with
        | lolli :: t1 -> 
          let bind_b4 = !bind_len in
          atoms := form :: t;
          (*Removing the top of the stack, so that a new one is pushed 
           with a smaller list of formulas to backtrack on.*)
          Stack.pop !states; nstates := !nstates - 1; 
          save_state (PRED(str, terms)) BODY 0 bind_b4 suc fail t1;
          let st = !nstates in
          solve_atm_aux suc (fun () -> print_endline "Fail: 435"; restore_atom st) forms
        | [] -> print_string ("No clauses for this atom: "^str^".\n"); print_string "Backtracking...\n"; fail ()
      end
        (*in attempt clauses (PRED (str, terms))*)
       with Not_found -> print_string "[ERROR] Atom not in table: "; print_string str; fail ()
    )
  | bla -> failwith "\nNot an atom in atoms' list"
  with 
    | Failure "hd" -> (*print_string "Strange failure"; print_endline "";*) suc ()

and restore_atom n = let s = Stack.length !states in
  print_string "Restoring states: "; print_int n; print_newline ();
  assert (n <= s);
  for i = 1 to s-n do
    let STATE(dt, _, _, _, bl, _, sc, fl,_) = Stack.pop !states in
      nstates := !nstates - 1
  done;
  let STATE(dt, _, _, _, bl, _, sc, fl,bck) = Stack.top !states in
  reset dt;
  restore_state bl;
  print_stack !states;
  (*print_hashtbl !context;*)
  back_chain bck sc fl
;;


