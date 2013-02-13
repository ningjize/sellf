(*
 * A hashtable implements the context of a sequent. The key is the
 * name of the subexponential, and this is mapped to a list of formulas.
 * The linear formulas (not marked with ?l) are stored with the key '$gamma'.
 * The formulas of specification of systems are stored with the key '$infty'
 *
 * Giselle Machado Reis - 2012
 *)

(* TODO organize the context module! *)

open Basic
open Term
open Subexponentials
open Prints

(* Initial context, will be set depending on what we want to prove *)
let initial : (string, terms list) Hashtbl.t = Hashtbl.create 100 ;;

(* This holds the formulas that could be consumed by a top rule *)
let erasableByTop : (string, terms list) Hashtbl.t ref = ref (Hashtbl.create 100) ;;

let initSubexp s = Hashtbl.add initial s [] ;;

let store form subexp = try match Hashtbl.find initial subexp with
  | l -> Hashtbl.replace initial subexp (form :: l)
  with Not_found -> failwith ("Subexponential "^subexp^" not in context.")
;;

(* Clears all subexponentials *)
let clearInitial () = Hashtbl.iter (fun k d -> Hashtbl.replace initial k []) initial;;

(* Create proper contexts for each functionality of the system *)

let createCutCoherenceContext () = 
  (* Adding cut rules' specifications *)
  List.iter (fun e -> store e "$infty") !Specification.cutRules ;;
  
let createInitialCoherenceContext () = 
  (* Adding identity rules' specifications *)
  List.iter (fun e -> store e "$infty") !Specification.axioms ;;
  
let createProofSearchContext () = 
  (* Adding rules' specifications (proof search without cut) *)
  List.iter (fun e -> store e "$infty") !Specification.axioms;
  List.iter (fun e -> store e "$infty") !Specification.introRules;
  List.iter (fun e -> store e "$infty") !Specification.structRules ;;
 
module Context = 
  struct
  
  type context = {
    hash : (string, terms list) Hashtbl.t;
  }

  (* Creates an empty context *)
  let createEmpty () = {
    hash = Hashtbl.create 100
  }

  let create h = {
    hash = h
  }

  (* Initialize a context with the formulas parsed *)
  let getInitial () = create initial

  let initialize () =
    (* \Gamma context (linear): stores the formulas that have no exponential *)
    initSubexp "$gamma";
    (* \infty context (classical): stores specifications *)
    initSubexp "$infty"

  (* All methods that operate on the context should return a new context with the proper modifications *)

  (* Adds a formula to a context *)
  let add ctx form subexp = 
    try match Hashtbl.find ctx.hash subexp with
      | forms -> 
        let newctx = Hashtbl.copy ctx.hash in
        Hashtbl.replace newctx subexp (form :: forms); 
        create newctx
      with Not_found -> failwith ("Subexponential "^subexp^" not in context.")

  (* Removes a formula (if it is linear) *)
  let remove ctx form subexp = 
    match type_of subexp with
      | LIN | AFF ->
        let newctx = Hashtbl.copy ctx.hash in
        let forms = Hashtbl.find newctx subexp in
        (* Removes the first occurence of form on the list. This can be implemented better *)
        let newforms = remove form forms in
        Hashtbl.replace newctx subexp newforms;
        create newctx
      | UNB | REL -> create (Hashtbl.copy ctx.hash)
  
  (* Delets a formula (unconditional) *)
  let delete ctx form subexp = try 
    let newctx = Hashtbl.copy ctx.hash in
    let forms = Hashtbl.find newctx subexp in
    (* Removes the first occurence of form on the list. This can be implemented better *)
    let newforms = Basic.remove form forms in
    Hashtbl.replace newctx subexp newforms;
    create newctx
    with _ -> 
      print_endline ("Trying to delete "^(termToString form)^" from "^subexp^" in:");
      print_endline ("CONTEXT\n"^(Hashtbl.fold (fun k d acc -> "["^k^"] "^(termsListToString d)^"\n"^acc) ctx.hash ""));
      failwith "Exception on deletion of formula from the context. "

  (* Returns the input context for the application of bang *)
  let bangin ctx subexp = 
    let newctx = Hashtbl.copy ctx.hash in
    Hashtbl.iter (fun idx forms ->
      match idx with
        (* Unbouded context  *)
        | "$infty" -> ()
        (* For every subexponential s < s holds. *)
        | s when s = subexp -> ()
        (* Formulas with no exponential must be erased *)
        | "$gamma" -> Hashtbl.replace newctx "$gamma" []
        (* These are deleted independently of being linear or classical *)
        | s -> 
          if not (greater_than s subexp) then Hashtbl.replace newctx s []
    ) ctx.hash;
    create newctx

  (* Returns the output context for the application of bang *)
  let bangout ctx subexp = 
    let newctx = Hashtbl.copy ctx.hash in
    Hashtbl.iter (fun idx forms ->
      match idx with
        (* These will always go to the out context  *)
        | "$gamma" | "$infty" -> ()
        | s -> match type_of s with
          (* Linear formulas that were in the input should not be available here. *)
          | LIN | AFF ->
            if (greater_than s subexp) || (s = subexp) then 
              Hashtbl.replace newctx s []
          (* Classical formulas are always available *)
          | UNB | REL -> ()
    ) ctx.hash;
    create newctx

  (* TODO: implement equality *)
  let equals ctx1 ctx2 = true 

  (* Checks if all linear contexts are empty (ignoring the formulas that could
  be erased by a top rule) *)
  let isLinearEmpty ctx = List.length ( 
    Hashtbl.fold (fun idx forms acc ->
      match type_of idx with
        | LIN | AFF -> begin 
          (* Finds the formulas that could be erased by top *)
          try match Hashtbl.find !erasableByTop idx with
            | erasable ->
              let newforms = List.filter (fun e -> not (List.mem e erasable)) forms in
              newforms @ acc
            with Not_found -> forms @ acc
        end
        | UNB | REL -> acc
    ) ctx.hash [] 
  ) == 0

  (* Marks the formulas of this context as erasable because a top rule was
  applied. *)
  let markErasable ctx = Hashtbl.iter (fun idx forms ->
    try match Hashtbl.find !erasableByTop idx with
      | formlst ->
        Hashtbl.replace !erasableByTop idx (formlst @ forms); 
      with Not_found -> Hashtbl.add !erasableByTop idx forms;
  ) ctx.hash

  (* Merges two contexts *)
  let merge ctx1 ctx2 = 
    let newctx = Hashtbl.copy ctx1.hash in
    Hashtbl.iter (fun idx forms ->
      match type_of idx with
        | LIN | AFF -> (
          try match Hashtbl.find newctx idx with
            | f -> Hashtbl.replace newctx idx (forms @ f)
          with Not_found -> failwith "Trying to merge two contexts with different subexponentials"
          )
        | UNB | REL -> ()
    ) ctx2.hash;
    create newctx

  let toPairs ctx = Hashtbl.fold (fun key data acc -> 
    let rec pairs k lst = match lst with
      | [] -> []
      | elm :: tl -> (k, elm) :: pairs k tl
    in
    (pairs key data) @ acc
    ) ctx.hash []

  let toString ctx = "CONTEXT\n"^(Hashtbl.fold (fun k d acc -> "["^k^"] "^(termsListToString d)^"\n"^acc) ctx.hash "")

  end
;;

module ContextSchema = struct
 
  let global : (string, int) Hashtbl.t = Hashtbl.create 100 ;;

  type context = {
    hash : (string, int) Hashtbl.t;
  }

  let create () = { 
    hash = Hashtbl.create 100
  }

  let createWith h = {
    hash = h
  }

  let initialize ctx = 
    let subexps = keys subexTpTbl in
    List.iter (fun s -> Hashtbl.add ctx.hash s 0; Hashtbl.add global s 0) subexps;
    ctx

  let copy ctx = createWith (Hashtbl.copy ctx.hash)
  
  let getIndex ctx s = try match Hashtbl.find ctx.hash s with
    | i -> i
    with Not_found -> failwith ("Subexponential "^s^" not in context.")

  let getContexts ctx = Hashtbl.fold (fun k v acc -> (k, v) :: acc) ctx.hash []

  let toString ctx = Hashtbl.fold (fun n i acc -> n ^ "_" ^ (string_of_int i) ^ ", " ^ acc) ctx.hash ""

  (* Creates the next context where the index of subexp is updated *)
  let next ctx subexp =
    let index = Hashtbl.find global subexp in
    let newctxhash = Hashtbl.copy ctx.hash in
    Hashtbl.replace newctxhash subexp (index + 1);
    Hashtbl.replace global subexp (index + 1);
    createWith newctxhash

  (* Creates the next context after inserting a formula in subexp *)
  let insert ctx subexp = 
    let index = Hashtbl.find global subexp in
    let newctxhash = Hashtbl.copy ctx.hash in
    Hashtbl.replace newctxhash subexp (index+2);
    Hashtbl.replace global subexp (index+2);
    createWith newctxhash

  (* Creates the two resulting contexts after a split *)
  let split ctx = 
    let hashctx1 = Hashtbl.copy ctx.hash in
    let hashctx2 = Hashtbl.copy ctx.hash in
    Hashtbl.iter (fun s i -> match type_of s with
      | LIN | REL -> 
        (* Global number for this subexponential *)
        let n = Hashtbl.find global s in
        (* Updating the global counter of s *)
        Hashtbl.replace global s (n+2);
        (* Configuring a new s context for each branch *)
        Hashtbl.replace hashctx1 s (n+1);
        Hashtbl.replace hashctx2 s (n+2);
      | UNB | AFF -> ()
    )  ctx.hash;
    (createWith hashctx1, createWith hashctx2)

  (* Creates the resulting context after a bang - increments the indices of
  those contexts that have their formulas erased *)
  let bang ctx subexp = 
    let hashctx = Hashtbl.copy ctx.hash in
    Hashtbl.iter (fun s i -> match type_of s with
      | LIN | REL -> ()
      | UNB | AFF -> 
        if s = subexp || (greater_than s subexp) then ()
        else begin
          let n = Hashtbl.find global s in
          Hashtbl.replace global s (n+1);
          Hashtbl.replace hashctx s (n+1)
        end
    ) ctx.hash;
    createWith hashctx

  end
;;
