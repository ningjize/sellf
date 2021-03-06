(*****************************************)
(*                                       *)
(*          Generic context              *)
(*                                       *)
(*  Giselle Reis                         *)
(*  2013                                 *)
(*                                       *)
(*****************************************)

open Prints

module type CONTEXTSCHEMA = 
  sig
    type context = { hash : (string, int) Hashtbl.t; }
    val global : (string, int) Hashtbl.t
    val createFresh : unit -> context
    val copy : context -> context
    val getIndex : context -> string -> int
    val getContexts : context -> (string * int) list
    val toString : context -> string    
    val toTexString : context -> string
    val ctxToTex : string * int -> string
    val ctxToStr : string * int -> string
    val insert : context -> string -> context
    val split : context -> context * context
    val bang : context -> string -> context
  end

module ContextSchema : CONTEXTSCHEMA = struct 

  let global : (string, int) Hashtbl.t = Hashtbl.create 100 ;;

  type context = {
    hash : (string, int) Hashtbl.t;
  }

  let create h = {
    hash = h
  }

  let createFresh () = 
    let subexps = Subexponentials.getAll () in
    let fresh = Hashtbl.create 100 in
    List.iter ( fun s ->
      try match Hashtbl.find global s with
	| n ->
	  Hashtbl.replace global s (n+1);
	  Hashtbl.add fresh s (n+1)
	with Not_found ->
	  Hashtbl.add global s 0;
	  Hashtbl.add fresh s 0
    ) subexps;
    create fresh

  let copy ctx = create (Hashtbl.copy ctx.hash)

  let getIndex ctx s = try match Hashtbl.find ctx.hash s with
    | i -> i
    with Not_found -> failwith ("Subexponential "^s^" not in context.")

  let getContexts ctx = Hashtbl.fold (fun k v acc -> (k, v) :: acc) ctx.hash []

  let toString ctx = Hashtbl.fold (fun n i acc -> n ^ "_" ^ (string_of_int i) ^ ", " ^ acc) ctx.hash ""

  let toTexString ctx = Hashtbl.fold (fun n i acc -> "\\Gamma_{" ^ n ^ "}^{" ^ (string_of_int i) ^ "} ; " ^ acc) ctx.hash ""

  let ctxToTex (s, i) = 
    ("\\Gamma_{"^s^"}^{"^(string_of_int i)^"}")

  let ctxToStr (s, i) = 
    ""^s^"_"^(string_of_int i)^""

  (* Creates the next context after inserting a formula in subexp *)
  let insert ctx subexp =
    let index = Hashtbl.find global subexp in
    let newctxhash = Hashtbl.copy ctx.hash in
    Hashtbl.replace newctxhash subexp (index + 1);
    Hashtbl.replace global subexp (index + 1);
    create newctxhash

  (* Creates the two resulting contexts after a split *)
  let split ctx = 
    let hashctx1 = Hashtbl.copy ctx.hash in
    let hashctx2 = Hashtbl.copy ctx.hash in
    Hashtbl.iter (fun s i -> match Subexponentials.type_of s with
      | Subexponentials.LIN | Subexponentials.REL -> 
	(* Global number for this subexponential *)
	let n = Hashtbl.find global s in
	(* Updating the global counter of s *)
	Hashtbl.replace global s (n+2);
	(* Configuring a new s context for each branch *)
	Hashtbl.replace hashctx1 s (n+1);
	Hashtbl.replace hashctx2 s (n+2);
      | Subexponentials.UNB | Subexponentials.AFF -> ()
    )  ctx.hash;
    (create hashctx1, create hashctx2)

  (* Creates the resulting context after a bang - increments the indices of
  those contexts that have their formulas erased *)
  let bang ctx subexp = 
    let hashctx = Hashtbl.copy ctx.hash in
    Hashtbl.iter (fun s i -> match Subexponentials.type_of s with
      | Subexponentials.LIN | Subexponentials.REL -> ()
      | Subexponentials.UNB | Subexponentials.AFF -> 
	if s = subexp || (Subexponentials.greater_than s subexp) then ()
	else begin
	  let n = Hashtbl.find global s in
	  Hashtbl.replace global s (n+1);
	  Hashtbl.replace hashctx s (n+1)
	end
    ) ctx.hash;
    create hashctx
end;;

