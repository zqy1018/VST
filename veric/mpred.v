Require Import VST.veric.base.
Require Import VST.veric.rmaps.
Require Export compcert.cfrontend.Ctypes.
Require Import VST.veric.compcert_rmaps.

Require Import VST.veric.composite_compute.
Require Import VST.veric.align_mem.
Require Import VST.veric.val_lemmas.

Require Export VST.veric.compspecs. (*new*)
Import compcert.lib.Maps.

Open Scope Z_scope.

Definition strict_bool_val (v: val) (t: type) : option bool :=
   match v, t with
   | Vint n, Tint _ _ _ => Some (negb (Int.eq n Int.zero))
   | Vlong n, Tlong _ _ => Some (negb (Int64.eq n Int64.zero))
   | (Vint n), (Tpointer _ _ | Tarray _ _ _ | Tfunction _ _ _ ) =>
            if Archi.ptr64 then None else if Int.eq n Int.zero then Some false else None
   | Vlong n, (Tpointer _ _ | Tarray _ _ _ | Tfunction _ _ _ ) =>
            if Archi.ptr64 then if Int64.eq n Int64.zero then Some false else None else None
   | Vptr b ofs, (Tpointer _ _ | Tarray _ _ _ | Tfunction _ _ _ ) => Some true
   | Vfloat f, Tfloat F64 _ => Some (negb(Float.cmp Ceq f Float.zero))
   | Vsingle f, Tfloat F32 _ => Some (negb(Float32.cmp Ceq f Float32.zero))
   | _, _ => None
   end.

Definition type_is_by_value (t:type) : bool :=
  match t with
  | Tint _ _ _
  | Tlong _ _
  | Tfloat _ _
  | Tpointer _ _ => true
  | _ => false
  end.

Definition type_is_by_reference t : bool :=
  match t with
  | Tarray _ _ _
  | Tfunction _ _ _ => true
  | _ => false
  end.

(** GENERAL KV-Maps **)

Set Implicit Arguments.
Module Map. Section map.
Variables (B : Type).

Definition t := positive -> option B.

Definition get (h: t) (a:positive) : option B := h a.

Definition set (a:positive) (v: B) (h: t) : t :=
  fun i => if ident_eq i a then Some v else h i.

Definition remove (a: positive) (h: t) : t :=
  fun i => if ident_eq i a then None else h i.

Definition empty : t := fun _ => None.

(** MAP Axioms **)

Lemma gss h x v : get (set x v h) x = Some v.
unfold get, set; if_tac; intuition.
Qed.

Lemma gso h x y v : x<>y -> get (set x v h) y = get h y.
unfold get, set; intros; if_tac; intuition.
Qed.

Lemma grs h x : get (remove x h) x = None.
unfold get, remove; intros; if_tac; intuition.
Qed.

Lemma gro h x y : x<>y -> get (remove x h) y = get h y.
unfold get, remove; intros; if_tac; intuition.
Qed.

Lemma ext h h' : (forall x, get h x = get h' x) -> h=h'.
Proof.
intros. extensionality x. apply H.
Qed.

Lemma override (a: positive) (b b' : B) h : set a b' (set a b h) = set a b' h.
Proof.
apply ext; intros; unfold get, set; if_tac; intuition. Qed.

Lemma gsspec:
    forall (i j: positive) (x: B) (m: t),
    get (set j x m) i = if ident_eq i j then Some x else get m i.
Proof.
intros. unfold get; unfold set; if_tac; intuition.
Qed.

Lemma override_same : forall id t (x:B), get t id = Some x -> set id x t = t.
Proof.
intros. unfold set. unfold get in H.  apply ext. intros. unfold get.
if_tac; subst; auto.
Qed.

End map.


End Map.
Unset Implicit Arguments.

(** Environment Definitions **)
Section FUNSPEC.

Definition genviron := Map.t block.

Definition venviron := Map.t (block * type).

Definition tenviron := Map.t val.

Inductive environ : Type :=
 mkEnviron: forall (ge: genviron) (ve: venviron) (te: tenviron), environ.

Definition ge_of (rho: environ) : genviron :=
  match rho with mkEnviron ge ve te => ge end.

Definition ve_of (rho: environ) : venviron :=
  match rho with mkEnviron ge ve te => ve end.

Definition te_of (rho: environ) : tenviron :=
  match rho with mkEnviron ge ve te => te end.

Definition any_environ : environ :=
  mkEnviron (fun _ => None)  (Map.empty _) (Map.empty _).

Definition mpred := pred rmap.

Definition argsEnviron:Type := genviron * (list val).

Definition AssertTT (A: TypeTree): TypeTree :=
  ArrowType A (ArrowType (ConstType environ) Mpred).

Definition ArgsTT (A: TypeTree): TypeTree :=
  ArrowType A (ArrowType (ConstType argsEnviron) Mpred).

Definition SpecTT (A: TypeTree): TypeTree :=
  ArrowType A (ArrowType (ConstType bool) (ArrowType (ConstType environ) Mpred)).

Definition SpecArgsTT (A: TypeTree): TypeTree :=
  ArrowType A 
  (PiType bool (fun b => ArrowType (ConstType 
                                         (if b 
                                          then argsEnviron
                                          else environ))
                                    Mpred)).

Definition super_non_expansive {A: TypeTree}
  (P: forall ts, dependent_type_functor_rec ts (AssertTT A) mpred): Prop :=
  forall n ts
    (x: functors.MixVariantFunctor._functor
                         (rmaps.dependent_type_functor_rec ts A) mpred)
    (rho: environ),
  approx n (P ts x rho) = approx n (P ts (fmap _ (approx n) (approx n) x) rho).

Definition args_super_non_expansive {A: TypeTree}
  (P: forall ts, dependent_type_functor_rec ts (ArgsTT A) mpred): Prop :=
  forall n ts
    (x: functors.MixVariantFunctor._functor
                         (rmaps.dependent_type_functor_rec ts A) mpred)
    (gargs: argsEnviron),
  @eq mpred (approx n (P ts x gargs)) (approx n (P ts (fmap _ (approx n) (approx n) x) gargs)).

Definition const_super_non_expansive: forall (T: Type) P,
  @super_non_expansive (ConstType T) P :=
  fun _ _ _ _ _ _ => eq_refl.

Definition AssertListTT (A: TypeTree): TypeTree :=
  ArrowType A (ArrowType (ConstType environ) (ListType Mpred)).

Definition super_non_expansive_list {A: TypeTree}
  (P: forall ts, dependent_type_functor_rec ts (AssertListTT A) mpred): Prop :=
  forall n ts
    (x: functors.MixVariantFunctor._functor
                         (rmaps.dependent_type_functor_rec ts A) mpred)
    (rho: environ),
  Forall2 (fun a b => approx n a = approx n b) (P ts x rho) (P ts (fmap _ (approx n) (approx n) x) rho).

Definition args_const_super_non_expansive: forall (T: Type) P,
  @args_super_non_expansive (ConstType T) P :=
  fun _ _ _ _ _ _ => eq_refl.

(*Potential alternative that does not use Ctypes
Inductive funspec :=
   mk_funspec: AST.signature -> forall (A: TypeTree)
     (P Q: forall ts, dependent_type_functor_rec ts (AssertTT A) mpred)
     (P_ne: super_non_expansive P) (Q_ne: super_non_expansive Q),
    funspec.
 *)

Inductive funspec :=
   mk_funspec: typesig -> calling_convention -> forall (A: TypeTree)
     (P: forall ts, dependent_type_functor_rec ts (ArgsTT A) mpred)
     (Q: forall ts, dependent_type_functor_rec ts (AssertTT A) mpred)
     (P_ne: args_super_non_expansive P) (Q_ne: super_non_expansive Q),
     funspec.

Definition varspecs : Type := list (ident * type).

Definition funspecs := list (ident * funspec).

End FUNSPEC.

(*Lenb: moved here from mapsto_memory_block.v*)
Definition assert := environ -> mpred.  (* Unfortunately
   can't export this abbreviation through SeparationLogic.v because
  it confuses the Lift system *)

Definition argsassert := argsEnviron -> mpred.

(*Lenb: moved packPQ here from res_predicates.v*)
Definition packPQ {A: rmaps.TypeTree}
  (P: forall ts, dependent_type_functor_rec ts (ArgsTT A) mpred)
  (Q: forall ts, dependent_type_functor_rec ts (AssertTT A) mpred):
  forall ts, dependent_type_functor_rec ts (SpecArgsTT A) mpred.
Proof. intros ts a b. destruct b. apply (P ts a). apply (Q ts a). Defined.

(*moved here from Clight_lemmas*)
Definition int_range (sz: intsize) (sgn: signedness) (i: int) :=
 match sz, sgn with
 | I8, Signed => -128 <= Int.signed i < 128
 | I8, Unsigned => 0 <= Int.unsigned i < 256
 | I16, Signed => -32768 <= Int.signed i < 32768
 | I16, Unsigned => 0 <= Int.unsigned i < 65536
 | I32, Signed => -2147483648 <= Int.signed i < 2147483648
 | I32, Unsigned => 0 <= Int.unsigned i < 4294967296
 | IBool, _ => 0 <= Int.unsigned i < 256
 end.

Definition in_members i (m: members): Prop :=
  In i (map fst m).

(*moved to compspecs.v
Definition members_no_replicate (m: members) : bool :=
  compute_list_norepet (map fst m).
*)

Definition compute_in_members id (m: members): bool :=
  id_in_list id (map fst m).

Lemma compute_in_members_true_iff: forall i m, compute_in_members i m = true <-> in_members i m.
Proof.
  intros.
  unfold compute_in_members.
  destruct (id_in_list i (map fst m)) eqn:HH;
  [apply id_in_list_true in HH | apply id_in_list_false in HH].
  + unfold in_members.
    tauto.
  + unfold in_members; split; [congruence | tauto].
Qed.

Lemma compute_in_members_false_iff: forall i m,
  compute_in_members i m = false <-> ~ in_members i m.
Proof.
  intros.
  pose proof compute_in_members_true_iff i m.
  rewrite <- H; clear H.
  destruct (compute_in_members i m); split; congruence.
Qed.

Ltac destruct_in_members i m :=
  let H := fresh "H" in
  destruct (compute_in_members i m) eqn:H;
    [apply compute_in_members_true_iff in H |
     apply compute_in_members_false_iff in H].

Lemma in_members_dec: forall i m, {in_members i m} + {~ in_members i m}.
Proof.
  intros.
  destruct_in_members i m; [left | right]; auto.
Qed.

Lemma size_chunk_sizeof: forall env t ch, access_mode t = By_value ch -> sizeof env t = Memdata.size_chunk ch.
Proof.
  intros.
  destruct t; inversion H.
  - destruct i, s; inversion H1; reflexivity.
  - destruct s; inversion H1; reflexivity.
  - destruct f; inversion H1; reflexivity.
  - inversion H1; reflexivity.
Qed.

(*Moved to compspecs.v
Definition composite_legal_fieldlist (co: composite): Prop :=
  members_no_replicate (co_members co) = true.

Definition composite_env_legal_fieldlist env :=
  forall (id : positive) (co : composite),
    env ! id = Some co -> composite_legal_fieldlist co.

Class compspecs := mkcompspecs {
  cenv_cs : composite_env;
  cenv_consistent: composite_env_consistent cenv_cs;
  cenv_legal_fieldlist: composite_env_legal_fieldlist cenv_cs;
  cenv_legal_su: composite_env_complete_legal_cosu_type cenv_cs;
  ha_env_cs: PTree.t Z;
  ha_env_cs_consistent: hardware_alignof_env_consistent cenv_cs ha_env_cs;
  ha_env_cs_complete: hardware_alignof_env_complete cenv_cs ha_env_cs;
  la_env_cs: PTree.t legal_alignas_obs;
  la_env_cs_consistent: legal_alignas_env_consistent cenv_cs ha_env_cs la_env_cs;
  la_env_cs_complete: legal_alignas_env_complete cenv_cs la_env_cs;
  la_env_cs_sound: legal_alignas_env_sound cenv_cs ha_env_cs la_env_cs
}.

Existing Class composite_env.
Existing Instance cenv_cs.*)

Arguments sizeof {env} !t / .
Arguments alignof {env} !t / .

Arguments sizeof_pos {env} t _.
Arguments alignof_pos {env} t.

Arguments complete_legal_cosu_type {cenv} !t / .

(* TODO: handle other part of compspecs like this. *)
Goal forall {cs: compspecs} t, sizeof t >= 0.
Proof. intros. apply sizeof_pos.
Abort.

(*
Definition compspecs_program (p: program): compspecs.
  apply (mkcompspecs (prog_comp_env p)).
  eapply build_composite_env_consistent.
  apply (prog_comp_env_eq p).
Defined.
*)

(*plays role of type_of_params *)
Fixpoint typelist_of_type_list (params : list type) : typelist :=
  match params with
  | nil => Tnil
  | ty :: rem => Tcons ty (typelist_of_type_list rem)
  end.

Definition type_of_funspec (fs: funspec) : type :=
  match fs with mk_funspec fsig cc _ _ _ _ _ => (*Tfunction (type_of_params (fst fsig)) (snd fsig) cc end.*)
Tfunction (typelist_of_type_list (fst fsig)) (snd fsig) cc end.

(*same definition as in Clight_core?*)
Fixpoint typelist2list (tl: typelist) : list type :=
 match tl with Tcons t r => t::typelist2list r | Tnil => nil end.

Lemma TTL1 l: typelist_of_type_list (map snd l) = type_of_params l.
Proof. induction l; simpl; trivial. destruct a. f_equal; trivial. Qed.

Lemma TTL2 l: (typlist_of_typelist (typelist_of_type_list l)) = map typ_of_type l.
Proof. induction l; simpl; trivial. f_equal; trivial . Qed.
(*
Lemma TTL3 l: typelist_of_type_list (Clight_core.typelist2list l) = l.
Proof. induction l; simpl; trivial. f_equal; trivial . Qed.
*)
Lemma TTL4 l: map snd l = typelist2list (type_of_params l).
Proof. induction l; simpl; trivial. destruct a. simpl. f_equal; trivial. Qed.

Lemma TTL5 {l}: typelist2list (typelist_of_type_list l) = l.
Proof. induction l; simpl; trivial. f_equal; trivial. Qed.

Definition idset := PTree.t unit.

Definition idset0 : idset := PTree.empty _.
Definition idset1 (id: ident) : idset := PTree.set id tt idset0.
Definition insert_idset (id: ident) (S: idset) : idset :=
  PTree.set id tt S.

Definition eval_id (id: ident) (rho: environ) := force_val (Map.get (te_of rho) id).

Definition env_set (rho: environ) (x: ident) (v: val) : environ :=
  mkEnviron (ge_of rho) (ve_of rho) (Map.set x v (te_of rho)).

Lemma eval_id_same: forall rho id v, eval_id id (env_set rho id v) = v.
Proof. unfold eval_id; intros; simpl. unfold force_val. rewrite Map.gss. auto.
Qed.
Hint Rewrite eval_id_same : normalize.

Lemma eval_id_other: forall rho id id' v,
   id<>id' -> eval_id id' (env_set rho id v) = eval_id id' rho.
Proof.
 unfold eval_id, force_val; intros. simpl. rewrite Map.gso; auto.
Qed.
Hint Rewrite eval_id_other using solve [clear; intro Hx; inversion Hx] : normalize.

Fixpoint make_tycontext_s (G: funspecs) :=
 match G with
 | nil => @PTree.Leaf funspec
 | (id,f)::r => PTree.set id f (make_tycontext_s r)
 end.

(* TWO ALTERNATE WAYS OF DOING LIFTING *)
(* LIFTING METHOD ONE: *)
Definition lift0 {B} (P: B) : environ -> B := fun _ => P.
Definition lift1 {A1 B} (P: A1 -> B) (f1: environ -> A1) : environ -> B := fun rho => P (f1 rho).
Definition lift2 {A1 A2 B} (P: A1 -> A2 -> B) (f1: environ -> A1) (f2: environ -> A2):
   environ -> B := fun rho => P (f1 rho) (f2 rho).
Definition lift3 {A1 A2 A3 B} (P: A1 -> A2 -> A3 -> B)
     (f1: environ -> A1) (f2: environ -> A2) (f3: environ -> A3) :  environ -> B :=
     fun rho => P (f1 rho) (f2 rho) (f3 rho).
Definition lift4 {A1 A2 A3 A4 B} (P: A1 -> A2 -> A3 -> A4 -> B)
     (f1: environ -> A1) (f2: environ -> A2) (f3: environ -> A3)(f4: environ -> A4):  environ -> B :=
     fun rho => P (f1 rho) (f2 rho) (f3 rho) (f4 rho).

Definition alift0 {B} (P: B) : argsEnviron -> B := fun _ => P.
Definition alift1 {A1 B} (P: A1 -> B) (f1: argsEnviron -> A1) : argsEnviron -> B := fun rho => P (f1 rho).
Definition alift2 {A1 A2 B} (P: A1 -> A2 -> B) (f1: argsEnviron -> A1) (f2: argsEnviron -> A2):
   argsEnviron -> B := fun rho => P (f1 rho) (f2 rho).
Definition alift3 {A1 A2 A3 B} (P: A1 -> A2 -> A3 -> B)
     (f1: argsEnviron -> A1) (f2: argsEnviron -> A2) (f3: argsEnviron -> A3) :  argsEnviron -> B :=
     fun rho => P (f1 rho) (f2 rho) (f3 rho).
Definition alift4 {A1 A2 A3 A4 B} (P: A1 -> A2 -> A3 -> A4 -> B)
     (f1: argsEnviron -> A1) (f2: argsEnviron -> A2) (f3: argsEnviron -> A3)(f4: argsEnviron -> A4):  argsEnviron -> B :=
     fun rho => P (f1 rho) (f2 rho) (f3 rho) (f4 rho).

(* LIFTING METHOD TWO: *)
Require Import VST.veric.lift.
Set Warnings "-projection-no-head-constant,-redundant-canonical-projection".
Canonical Structure LiftEnviron := Tend environ.
Set Warnings "projection-no-head-constant,redundant-canonical-projection".

Set Warnings "-projection-no-head-constant,-redundant-canonical-projection".
Canonical Structure LiftAEnviron := Tend argsEnviron.
Set Warnings "projection-no-head-constant,redundant-canonical-projection".

Ltac super_unfold_lift :=
  cbv delta [liftx LiftEnviron LiftAEnviron Tarrow Tend lift_S lift_T lift_prod
  lift_last lifted lift_uncurry_open lift_curry lift lift0 lift1 lift2 lift3 alift0 alift1 alift2 alift3] beta iota in *.

Lemma approx_hered_derives_e n P Q: predicates_hered.derives P Q -> predicates_hered.derives (approx n P) (approx n Q).
Proof. intros. unfold approx. intros m. simpl. intros [? ?]. split; auto. Qed.
Lemma approx_derives_e n P Q: P |-- Q -> approx n P |-- approx n Q.
Proof. intros. apply approx_hered_derives_e. apply H. Qed. 

Lemma hered_derives_derives P Q: predicates_hered.derives P Q -> derives P Q.
Proof. trivial. Qed.
