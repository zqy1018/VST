Require Import VST.veric.rmaps.
Require Import VST.concurrency.ghosts.
Require Import VST.concurrency.conclib.
Require Import VST.concurrency.fupd.
Require Import VST.concurrency.invariants.
Require Import VST.atomics.acq_rel_atomics.
Require Import VST.atomics.maps.
Require Import VST.floyd.library.
Require Import VST.floyd.sublist.
Require Import VST.atomics.hashtable_atomic_ra.
Require Import VST.atomics.hashtable.
Require Import VST.atomics.general_atomics.
Import List.

Set Bullet Behavior "Strict Subproofs".

Instance CompSpecs : compspecs. make_compspecs prog. Defined.
Definition Vprog : varspecs. mk_varspecs prog. Defined.

Definition makelock_spec := DECLARE _makelock (makelock_spec _).
Definition freelock2_spec := DECLARE _freelock2 (freelock2_spec _).
Definition acquire_spec := DECLARE _acquire acquire_spec.
Definition release2_spec := DECLARE _release2 release2_spec.
Definition spawn_spec := DECLARE _spawn spawn_spec.
Definition load_acq_spec := DECLARE _load_acq load_acq_spec.
(*Definition store_rel_spec := DECLARE _store_rel store_rel_spec'.*)
Definition CAS_RA_spec := DECLARE _CAS_RA CAS_RA_spec.

Definition surely_malloc_spec :=
 DECLARE _surely_malloc
   WITH t : type, gv : globals
   PRE [ _n OF tuint ]
       PROP (0 <= sizeof t <= Int.max_unsigned; complete_legal_cosu_type t = true;
             natural_aligned natural_alignment t = true)
       LOCAL (temp _n (Vint (Int.repr (sizeof t))); gvars gv)
       SEP (mem_mgr gv)
    POST [ tptr tvoid ] EX p:_,
       PROP ()
       LOCAL (temp ret_temp p)
       SEP (mem_mgr gv; malloc_token Ews t p; data_at_ Ews t p).

Definition integer_hash_spec :=
 DECLARE _integer_hash
  WITH i : Z
  PRE [ _i OF tint ]
   PROP () LOCAL (temp _i (vint i)) SEP ()
  POST [ tint ]
   PROP () LOCAL (temp ret_temp (vint (i * 654435761))) SEP ().
(* One might think it should just return an unknown number, but in fact it needs to follow a known hash
   function at the logic level to be useful. *)

Definition tentry := Tstruct _entry noattr.

(* Having size as a large known constant tends to make everything slow, so here's a hack. *)
Definition has_size : {x : Z | x = 16384}.
Proof.
  eexists; eauto.
Qed.

Instance hf1 : hash_fun := { size := proj1_sig has_size; hash i := (i * 654435761) mod (proj1_sig has_size) }.
Proof.
  - rewrite ->(proj2_sig has_size); computable.
  - intro; apply Z_mod_lt; rewrite ->(proj2_sig has_size); computable.
Defined.

(* The top-level structure we get with release-acquire is a hashtable mapping each key to a history of values
   stored there, where a get_item may get any value at least as late as the last one it saw (or fail if it has never
   succeeded before). However, we can't enforce this with the protocol because of the write-write race on the value;
   each write must move the protocol to a final state, so there can be no history in the transition system. *)

Definition value_of (m : _ -> option Z) v := exists j, log_latest m j v.

Lemma value_of_0 : value_of (ghosts.singleton O 0) 0.
Proof.
  eexists; apply log_latest_singleton.
Qed.
Hint Resolve value_of_0.

(* If we're going to do a store_rel to a location, we can't expect to get resources out of it.
   In fact, unless we CAS, Tfull is *only* an obligation, not an available resource. *)
(* This definition is unsuitable for set_item (because it has a nontrivial full interpretation), and weaker
   than useful for the other functions.
Definition v_T sh g s (v : Z) := EX log : Z -> option Z, !!(s = v /\ value_of log v) &&
  ghost (sh, log) g.
*)

Definition v_T sh g s (v : Z) := !!(value_of s v /\ (v = 0 -> forall j v', s j = Some v' -> v' = 0)) &&
  @ghost_master _ _ fmap_order sh s g.

Instance v_prot g : protocol (v_T Share.bot g) (v_T gsh2 g).
Proof.
  split; intros; unfold v_T.
  - iIntros "[% H]".
    iMod (make_snap(ORD := fmap_order) with "H") as "[$ $]"; auto.
  - apply prop_duplicable, ghost_snap_duplicable.
Qed.

Notation v_T' g := (v_T Share.bot g, v_T gsh2 g).

Notation v_state i lg l s := (protocol_A l s map_incl (v_T' (Znth i lg))).

(* We don't need histories for keys, but we do need to know that a non-zero key is persistent. *)
Definition zero_ord a b := a = 0 \/ a = b.

Instance zero_RA : Ghost := { valid a := True;
  Join_G a b c := if eq_dec a 0 then c = b else a = c /\ zero_ord b c }.
Proof.
  - exists (fun _ => 0); auto; intro.
    hnf; auto.
  - constructor.
    + intros; hnf in *.
      destruct (eq_dec _ _); subst; auto.
      unfold zero_ord in *; omega.
    + intros; hnf in *.
      destruct (eq_dec _ _), (eq_dec _ _); subst; eexists; split; hnf; auto.
      * rewrite ->if_false; auto.
      * unfold zero_ord in *; rewrite -> if_true by omega; auto.
      * rewrite -> if_true by omega; auto.
      * unfold zero_ord in *.
        instantiate (1 := if eq_dec b 0 then c else b).
        if_tac; auto; omega.
      * rewrite -> if_false by auto.
        unfold zero_ord in *.
        if_tac; omega.
    + intros; hnf in *.
      unfold zero_ord in *; if_tac; destruct (eq_dec _ _); subst; auto; omega.
    + intros; hnf in *.
      destruct (eq_dec _ _), (eq_dec _ _); unfold zero_ord in *; omega.
  - auto.
Defined.

Instance zero_order : PCM_order zero_ord.
Proof.
  constructor; first constructor; repeat intro; unfold zero_ord in *; auto; try omega.
  - exists (if eq_dec a 0 then b else a); split; hnf; destruct (eq_dec _ _); auto.
    unfold zero_ord; omega.
  - hnf in H.
    destruct (eq_dec _ _); auto.
    unfold zero_ord in *; omega.
  - hnf.
    if_tac; auto; omega.
Qed.

Definition k_T (sh : share) g s v := !!(s = v) && ghost_master sh v g.

Instance k_prot g : protocol (k_T Share.bot g) (k_T gsh2 g).
Proof.
  split; intros; unfold k_T.
  - iIntros "[% H]".
    iMod (make_snap with "H") as "[$ $]"; auto.
  - apply prop_duplicable, ghost_snap_duplicable.
Qed.

Notation k_T' g := (k_T Share.bot g, k_T gsh2 g).

Notation k_state i lg l s := (protocol_A l s zero_ord (k_T' (Znth i lg))).

(* lookup doesn't really depend on the type of values. *)
Definition lookup' {B} (T : list (Z * B)) := lookup (combine (map fst T) (repeat 0 (Z.to_nat size))).

Definition wf_table (T : list (Z * (nat -> option Z))) := forall k i, k <> 0 -> fst (Znth i T) = k ->
  lookup' T k = Some i.

Definition hashtable_entry (T : list (Z * (_ -> option Z))) lgk lgv i :=
  let '(k, lv) := Znth i T in !!(exists v, value_of lv v /\ (k = 0 -> v = 0) /\
    (v = 0 -> forall j v', lv j = Some v' -> v' = 0)) &&
  ghost_master gsh1 k (Znth i lgk) * @ghost_master _ _ fmap_order gsh1 lv (Znth i lgv).

Existing Instance exclusive_PCM.

(* The hashtable assertion contains all the ghost state of the SC version, but no data;
   the protocols enforce the relationship between the ghost state and the data. *)
Definition hashtable H g lgk lgv := EX T : list (Z * (nat -> option Z)),
  !!(Zlength T = size /\ wf_table T /\
     forall k lv, H k = Some lv <-> In (k, lv) T /\ exists v, value_of lv v /\ v <> 0) &&
  excl g H * iter_sepcon (hashtable_entry T lgk lgv) (upto (Z.to_nat size)).

Definition hashtable_entry_A T lgk lgv entries i := let '(pk, pv) := Znth i entries in
  let '(k, lv) := Znth i T in !!(exists v, value_of lv v /\ (k = 0 -> v = 0) /\
    (v = 0 -> forall j v', lv j = Some v' -> v' = 0)) && k_state i lgk pk k * v_state i lgv pv lv.

Definition hashtable_A T lgk lgv entries :=
  iter_sepcon (hashtable_entry_A T lgk lgv entries) (upto (Z.to_nat size)).

Definition HT_upd (H : Z -> option (_ -> option Z)) k v H' := exists lv, H' = map_upd H k lv /\ value_of lv v /\
  match H k with Some lv0 => map_incl lv0 lv | None => True end.

Definition table_incl (T1 T2 : list (Z * (nat -> option Z))) := forall i,
  zero_ord (fst (Znth i T1)) (fst (Znth i T2)) /\
  map_incl (snd (Znth i T1)) (snd (Znth i T2)).

(*Program Definition set_item_spec := DECLARE _set_item atomic_spec
  (ConstType (Z * Z * val * share * list (val * val) * gname * list gname * list gname * list (Z * (Z -> option Z))))
  [(_key, tint); (_value, tint)] tvoid
  [fun _ '(k, v, p, sh, entries, g, lgk, lgv, T0) => temp _key (vint k);
   fun _ '(k, v, p, sh, entries, g, lgk, lgv, T0) => temp _value (vint v);
   fun _ '(k, v, p, sh, entries, g, lgk, lgv, T0) => gvar _m_entries p]
  (fun _ '(k, v, p, sh, entries, g, lgk, lgv, T0) => !!(readable_share sh /\ repable_signed k /\ repable_signed v /\
   k <> 0 /\ v <> 0 /\ Forall (fun '(pk, pv) => isptr pk /\ isptr pv) entries /\ Zlength lgk = size /\ Zlength lgv = size /\
   Zlength T0 = size(* /\ wf_table T0*)) &&
   data_at sh (tarray tentry size) entries p * hashtable_A T0 lgk lgv entries)
  (fun _ '(k, v, p, sh, entries, g, lgk, lgv, T0) H => hashtable H g lgk lgv)
  tt []
  (fun _ '(k, v, p, sh, entries, g, lgk, lgv, T0) H _ => data_at sh (tarray tentry size) entries p *
   EX T : _, !!(table_incl T0 T /\ Zlength T = size /\ (*wf_table T /\*) exists i lv, lookup' T k = Some i /\
   Znth i T = (k, lv) /\ value_of lv v) && hashtable_A T lgk lgv entries)
  (fun _ '(k, v, p, sh, entries, g, lgk, lgv, T0) H _ => EX H' : _, !!(HT_upd H k v H') &&
   hashtable H' g lgk lgv)
  _ _ _ _ _ _.
Next Obligation.
Proof.
  intros ?? w; decompose [prod] w; auto.
Qed.
Next Obligation.
Proof.
  intros ?? w; decompose [prod] w; auto.
Qed.
Next Obligation.
Proof.
  intros ?? w; decompose [prod] w; auto.
Qed.
Next Obligation.
Proof.
  intros ?? w; decompose [prod] w; auto.
Qed.
Next Obligation.
Proof.
  intros ?? w; decompose [prod] w; auto.
Qed.
Next Obligation.
Proof.
  intros ?? w; decompose [prod] w; auto.
Qed.*)

(* get_item_spec must be more relaxed. Reading a 0 doesn't guarantee the key is absent,
   and the value read can be arbitrarily outdated. *)
Program Definition get_item_spec := DECLARE _get_item
  ATOMIC TYPE (ConstType (Z * globals * share * list (val * val) * gname * list gname * list gname * list (Z * (_ -> option Z)))) OBJ H INVS empty top
  WITH k : _, gv : _, sh : _, entries : _, g : _, lgk : _, lgv : _, T0 : _
  PRE [ _key OF tint ]
    PROP (readable_share sh; repable_signed k; k <> 0;
      Forall (fun '(pk, pv) => isptr pk /\ isptr pv) entries; Zlength lgk = size; Zlength lgv = size; Zlength T0 = size (*/\ wf_table T0*))
    LOCAL (temp _key (vint k); gvars gv)
    SEPS (data_at sh (tarray tentry size) entries (gv _m_entries); hashtable_A T0 lgk lgv entries) | (hashtable H g lgk lgv)
  POST [ tint ]
   EX x : Z * (nat -> option Z),
    PROP ()
    LOCAL (temp ret_temp (vint (fst x)))
    SEP (let '(v, lv) := x in data_at sh (tarray tentry size) entries (gv _m_entries) *
      EX T : _, !!(table_incl T0 T /\ Zlength T = size /\ (*wf_table T /\*) exists i,
        lookup' T k = Some i /\ snd (Znth i T) = lv) && hashtable_A T lgk lgv entries *
        (!!(value_of lv v /\ (v <> 0 -> exists lv', H k = Some lv' /\ map_incl lv lv')) && hashtable H g lgk lgv)).

Program Definition add_item_spec := DECLARE _add_item
  ATOMIC TYPE  (ConstType (Z * Z * globals * share * list (val * val) * gname * list gname * list gname * list (Z * (_ -> option Z)))) OBJ H INVS empty top
  WITH k : _, v : _, gv : _, sh : _, entries : _, g : _, lgk : _, lgv : _, T0 : _
  PRE [ _key OF tint, _value OF tint ]
    PROP (readable_share sh; repable_signed k; repable_signed v; k <> 0; v <> 0;
      Forall (fun '(pk, pv) => isptr pk /\ isptr pv) entries; Zlength lgk = size; Zlength lgv = size; Zlength T0 = size (*/\ wf_table T0*))
    LOCAL (temp _key (vint k); temp _value (vint v); gvars gv)
    SEPS (data_at sh (tarray tentry size) entries (gv _m_entries); hashtable_A T0 lgk lgv entries) | (hashtable H g lgk lgv)
  POST [ tint ]
   EX x : bool * (nat -> option Z),
    PROP ()
    LOCAL (temp ret_temp (Val.of_bool (fst x)))
    SEP (let '(b, lv) := x in data_at sh (tarray tentry size) entries (gv _m_entries) *
   EX T : _, !!(table_incl T0 T /\ Zlength T = size (*/\ wf_table T*) /\ exists i, lookup' T k = Some i /\
     Znth i T = (k, lv)) && hashtable_A T lgk lgv entries *
   (!!((H k = None <-> b = true) /\ (b = true -> value_of lv v)) &&
     hashtable (if b then map_upd H k lv else H) g lgk lgv)).

Definition init_table_spec :=
 DECLARE _init_table
  WITH gv : globals
  PRE [ ]
   PROP ()
   LOCAL (gvars gv)
   SEP (mem_mgr gv; data_at_ Ews (tarray tentry size) (gv _m_entries))
  POST [ tvoid ]
   EX entries : list (val * val), EX g : gname, EX lgk : list gname, EX lgv : list gname,
   PROP (Forall (fun '(pk, pv) => isptr pk /\ isptr pv) entries; Zlength lgk = size; Zlength lgv = size)
   LOCAL ()
   SEP (mem_mgr gv; data_at Ews (tarray tentry size) entries (gv _m_entries); iter_sepcon (fun '(pk, pv) =>
          malloc_token Ews tint pk * malloc_token Ews tint pv) entries;
        hashtable empty_map g lgk lgv;
        hashtable_A (repeat (0, ghosts.singleton O 0) (Z.to_nat size)) lgk lgv entries).

Inductive hashtable_hist_el :=
  | HSet (k : Z) (v : Z) | HGet (k : Z) (v : Z) | HAdd (k : Z) (v : Z) (r : bool).

Notation hist := (list (nat * hashtable_hist_el)).

Fixpoint apply_hist H h H' :=
  match h with
  | [] => H' = H
  | HSet k v :: h' => exists H1, HT_upd H k v H1 /\ apply_hist H1 h' H'
  | HGet k v :: h' => (v <> 0 -> exists lv, H k = Some lv /\ exists j, lv j = Some v) /\ apply_hist H h' H'
  | HAdd k v r :: h' => if r then H k = None /\ exists H1, HT_upd H k v H1 /\ apply_hist H1 h' H'
                        else H k <> None /\ apply_hist H h' H'
  end.

Definition hashtable_inv gh g lgk lgv := EX H : _, hashtable H g lgk lgv *
  EX hr : _, !!(apply_hist (fun _ => None) hr H) && ghost_ref hr gh.

Definition f_lock_inv N gv sh gsh entries gh g lgk lgv t lockt res (inv_names : invG) :=
  EX b1 : bool, EX b2 : bool, EX b3 : bool, EX h : _,
    !!(add_events empty_map [HAdd 1 1 b1; HAdd 2 1 b2; HAdd 3 1 b3] h) && ghost_hist gsh h gh *
    mem_mgr gv * data_at sh (tarray tentry size) entries (gv _m_entries) *
    invariant N (hashtable_inv gh g lgk lgv) * (EX T : _, hashtable_A T lgk lgv entries) *
    data_at sh (tarray (tptr tlock) 3) (upd_Znth t (repeat Vundef 3) lockt) (gv _thread_locks) *
    data_at sh (tarray (tptr tint) 3) (upd_Znth t (repeat Vundef 3) res) (gv _results) *
    data_at Ews tint (vint (Zlength (filter id [b1; b2; b3]))) res.

Definition f_lock_pred N gv tsh sh gsh entries gh g lgk lgv t lockt res inv_names :=
  selflock (f_lock_inv N gv sh gsh entries gh g lgk lgv t lockt res inv_names) tsh lockt.

Definition f_spec :=
 DECLARE _f
  WITH tid : val, x : iname * share * share * share * list (val * val) * gname * gname *
                      list gname * list gname * globals * Z * val * val * invG
  PRE [ _arg OF (tptr tvoid) ]
   let '(N, sh, gsh, tsh, entries, gh, g, lgk, lgv, gv, t, lockt, res, inv_names) := x in
   PROP (0 <= t < 3; isptr lockt; readable_share sh; readable_share tsh; gsh <> Share.bot;
         Forall (fun '(pk, pv) => isptr pk /\ isptr pv) entries; Zlength lgk = size; Zlength lgv = size)
   LOCAL (temp _arg tid; gvars gv)
   SEP (mem_mgr gv; data_at sh (tarray tentry size) entries (gv _m_entries); invariant N (hashtable_inv gh g lgk lgv);
        hashtable_A (repeat (0, ghosts.singleton O 0) (Z.to_nat size)) lgk lgv entries;
        ghost_hist(hist_el := hashtable_hist_el) gsh empty_map gh;
        data_at Ews tint (vint t) tid; malloc_token Ews tint tid;
        data_at sh (tarray (tptr tlock) 3) (upd_Znth t (repeat Vundef 3) lockt) (gv _thread_locks);
        data_at sh (tarray (tptr tint) 3) (upd_Znth t (repeat Vundef 3) res) (gv _results);
        data_at_ Ews tint res;
        lock_inv tsh lockt (f_lock_pred N gv tsh sh gsh entries gh g lgk lgv t lockt res inv_names))
  POST [ tptr tvoid ] PROP () LOCAL () SEP ().

Definition main_spec :=
 DECLARE _main
  WITH gv : globals
  PRE  [] main_pre prog nil gv
  POST [ tint ] main_post prog nil gv.

Definition Gprog : funspecs := ltac:(with_library prog [makelock_spec; freelock2_spec; acquire_spec;
  release2_spec; spawn_spec; surely_malloc_spec; load_acq_spec; CAS_RA_spec;
  integer_hash_spec; get_item_spec; add_item_spec; init_table_spec; f_spec; main_spec]).

Lemma body_integer_hash: semax_body Vprog Gprog f_integer_hash integer_hash_spec.
Proof.
  start_function.
  forward.
Qed.

Opaque upto.

Lemma hashtable_entry_A_duplicable : forall T lgk lgv entries i, duplicable (hashtable_entry_A T lgk lgv entries i).
Proof.
  intros; unfold hashtable_entry_A.
  destruct (Znth i entries), (Znth i T).
  apply sepcon_duplicable, protocol_A_duplicable.
  apply prop_duplicable, protocol_A_duplicable.
Qed.

Lemma hashtable_A_duplicable : forall T lgk lgv entries, duplicable (hashtable_A T lgk lgv entries).
Proof.
  intros; unfold hashtable_A.
  apply iter_sepcon_duplicable; intros.
  apply hashtable_entry_A_duplicable.
Qed.

Lemma zero_ord_0 : forall z, zero_ord 0 z.
Proof.
  unfold zero_ord; auto.
Qed.
Hint Resolve zero_ord_0.

Lemma lookup'_succeeds : forall k i i1 (T : list (Z * (nat -> option Z))) (Hk : k <> 0) (Hi : 0 <= i < size)
  (Hi1 : (i + hash k) mod size = i1 mod size) (HT : Zlength T = size)
  (Hfail : Forall (fun x => fst x <> 0 /\ fst x <> k) (sublist 0 i (rebase T (hash k))))
  (Hhit : fst (Znth (i1 mod size) T) = k \/ fst (Znth (i1 mod size) T) = 0),
  lookup' T k = Some (i1 mod size).
Proof.
  intros.
  assert (0 <= hash k < Zlength T) by (replace (Zlength T) with size; apply hash_range).
  assert (Zlength (map fst T) = Zlength (repeat 0 (Z.to_nat size))).
  { rewrite ->Zlength_map, Zlength_repeat, Z2Nat.id; auto; omega. }
  assert (Zlength (combine (map fst T) (repeat 0 (Z.to_nat size))) = size) as Hsize.
  { rewrite ->Zlength_combine, Z.min_l; auto; try omega; rewrite ->Zlength_map; auto. }
  assert (Zlength (rebase (combine (map fst T) (repeat 0 (Z.to_nat size))) (hash k)) = size).
  { rewrite ->Zlength_rebase; auto; omega. }
  assert (forall j, 0 <= j < size -> Znth j (rebase (combine (map fst T) (repeat 0 (Z.to_nat size))) (hash k)) =
    (fst (Znth ((j + hash k) mod size) T), 0)) as Hj.
  { intros; rewrite ->Znth_rebase, Znth_combine, Znth_repeat'; auto; try omega.
    erewrite Znth_map; rewrite ->Hsize; eauto.
    replace (Zlength T) with size; apply Z_mod_lt; omega.
    { rewrite ->Hsize, Z2Nat.id by omega; apply Z_mod_lt; omega. } }
  unfold lookup', lookup; rewrite ->index_of'_succeeds with (i := i).
  unfold option_map; congruence.
  { omega. }
  { rewrite ->Forall_forall_Znth.
    rewrite ->Zlength_sublist by omega; intros.
    rewrite ->Znth_sublist, Hj by (auto; omega).
    eapply Forall_Znth with (i2 := (i0 + 0)) in Hfail; [|rewrite Zlength_sublist; rewrite ->?Zlength_rebase; omega].
    rewrite ->Znth_sublist, Znth_rebase, Z.add_0_r in Hfail by omega; replace size with (Zlength T); eauto. }
  { rewrite ->Hj, Hi1; auto. }
Qed.

Lemma failed_entries : forall k i i1 keys lgk lgv T (Hk : k <> 0) (Hi : 0 <= i < size)
  (Hi1 : (i + hash k) mod size = i1 mod size) (HT : Zlength T = size) (Hlg : Zlength lgk = size)
  (Hkeys: Zlength keys = size)
  (Hfail : Forall (fun z => z <> 0 /\ z <> k) (sublist 0 i (rebase keys (hash k)))),
  iter_sepcon (hashtable_entry T lgk lgv) (remove_Znth (i1 mod size) (upto (Z.to_nat size))) *
  iter_sepcon (fun i => ghost_snap (Znth ((i + hash k) mod size) keys)
    (Znth ((i + hash k) mod size) lgk)) (upto (Z.to_nat i))
  |-- !! Forall (fun x => fst x <> 0 /\ fst x <> k) (sublist 0 i (rebase T (hash k))).
Proof.
  intros.
  rewrite -> Forall_forall, prop_forall; apply allp_right; intros (k', v').
  rewrite prop_forall; apply allp_right; intro Hin.
  apply In_Znth in Hin; destruct Hin as (j & Hj & Hjth).
  pose proof (hash_range k).
  erewrite Zlength_sublist in Hj by (rewrite ?Zlength_rebase; omega).
  rewrite -> Znth_sublist, Znth_rebase in Hjth by omega.
  assert (0 <= (j + hash k) mod size < size) by (apply Z_mod_lt, size_pos).
  pose proof (Z_mod_lt i1 _ size_pos).
  assert ((j + hash k) mod size <> i1 mod size).
  { rewrite <- Hi1; intro Heq.
    apply Zmod_plus_inv in Heq; [|apply size_pos].
    rewrite !Zmod_small in Heq; omega. }
  rewrite -> iter_sepcon_Znth_remove with (i0 := (j + hash k) mod size),
                    iter_sepcon_Znth' with (i0 := j)(l := upto _)
    by (auto; rewrite -> Zlength_upto, Z2Nat.id; try omega).
  rewrite -> !Znth_upto by (rewrite -> Z2Nat.id; omega).
  unfold hashtable_entry at 1.
  rewrite Z.add_0_r in Hjth; replace (Zlength T) with size in Hjth; rewrite Hjth.
  Intros; rewrite <- !sepcon_assoc.
  rewrite (sepcon_comm _ (ghost_snap _ _)).
  rewrite <- !sepcon_assoc, snap_master_join by auto.
  Intros; apply prop_right; simpl.
  eapply Forall_Znth in Hfail.
  rewrite -> Znth_sublist, Z.add_0_r, Znth_rebase with (i0 := j) in Hfail; auto; try omega.
  replace (Zlength keys) with size in Hfail.
  match goal with H : zero_ord _ _ |- _ => destruct H; [destruct Hfail; contradiction|] end.
  simpl in *; subst; intuition.
  { rewrite -> Zlength_sublist; auto; try omega.
    rewrite Zlength_rebase; omega. }
Qed.

Corollary entries_lookup : forall k i i1 keys lgk lgv T (Hk : k <> 0) (Hi : 0 <= i < size)
  (Hi1 : (i + hash k) mod size = i1 mod size) (HT : Zlength T = size) (Hlg : Zlength lgk = size)
  (Hkeys: Zlength keys = size)
  (Hfail : Forall (fun z => z <> 0 /\ z <> k) (sublist 0 i (rebase keys (hash k))))
  (Hhit : fst (Znth (i1 mod size) T) = k \/ fst (Znth (i1 mod size) T) = 0),
  iter_sepcon (hashtable_entry T lgk lgv) (remove_Znth (i1 mod size) (upto (Z.to_nat size))) *
  iter_sepcon (fun i => ghost_snap (Znth ((i + hash k) mod size) keys)
    (Znth ((i + hash k) mod size) lgk)) (upto (Z.to_nat i))
  |-- !! (lookup' T k = Some (i1 mod size)).
Proof.
  intros.
  eapply derives_trans; [apply failed_entries; eauto | apply prop_left; intro; apply prop_right].
  eapply lookup'_succeeds; eauto.
Qed.

Lemma wf_table_upd : forall T k v i (Hwf : wf_table T) (HT : Zlength T = size) (Hi : lookup' T k = Some i)
  (Hk : k <> 0), wf_table (upd_Znth i T (k, v)).
Proof.
  intros; intros ?? Hj ?.
  unfold lookup' in Hi.
  pose proof size_pos.
  assert (Zlength (map fst T) = Zlength (repeat 0 (Z.to_nat size))).
  { rewrite ->Zlength_map, ?Zlength_repeat, ?Z2Nat.id; auto; omega. }
  assert (Zlength (combine (map fst T) (repeat 0 (Z.to_nat size))) = size).
  { rewrite ->Zlength_combine, Z.min_l; auto; try omega; rewrite ->Zlength_map; auto. }
  exploit lookup_range; eauto.
  intros; unfold lookup'.
  erewrite <- upd_Znth_map, combine_upd_Znth1 by (auto; rewrite ->Zlength_map; omega).
  destruct (eq_dec i0 i); subst.
  - rewrite ->upd_Znth_same, lookup_upd_same; auto; omega.
  - rewrite ->upd_Znth_diff' in Hj |- * by (auto; omega); simpl.
    assert (lookup (combine (map fst T) (repeat 0 (Z.to_nat size))) (fst (Znth i0 T)) <> Some i).
    { specialize (Hwf (fst (Znth i0 T)) i0).
      unfold lookup' in Hwf; rewrite ->Hwf; auto; congruence. }
    rewrite ->lookup_upd_diff; eauto.
    split; auto.
    intro; specialize (Hwf k); unfold lookup' in Hwf.
    erewrite Hwf in Hi by eauto; congruence.
Qed.

Corollary wf_table_upd_same : forall T k v i (Hwf : wf_table T) (HT : Zlength T = size)
  (Hi : fst (Znth i T) = k) (Hk : k <> 0), wf_table (upd_Znth i T (k, v)).
Proof.
  intros; apply wf_table_upd; auto.
Qed.

Lemma hash_size : forall k, (k * 654435761) mod size = hash k mod size.
Proof.
  intro; simpl.
  rewrite ->Zmod_mod; split; auto; omega.
Qed.

Arguments size : simpl never.
Arguments hash : simpl never.

Lemma upd_entries : forall T lgk lgv i k lv v, value_of lv v -> (k = 0 -> v = 0) ->
  (v = 0 -> forall j v', lv j = Some v' -> v' = 0) -> Zlength T = size -> 0 <= i < size ->
  map (hashtable_entry (upd_Znth i T (k, lv)) lgk lgv) (upto (Z.to_nat size)) =
  upd_Znth i (map (hashtable_entry T lgk lgv) (upto (Z.to_nat size)))
    (ghost_master gsh1 k (Znth i lgk) * @ghost_master _ _ fmap_order gsh1 lv (Znth i lgv)).
Proof.
  intros; apply list_Znth_eq'.
  { rewrite ->upd_Znth_Zlength; rewrite ->!Zlength_map; auto.
    rewrite ->Zlength_upto, Z2Nat.id; auto; omega. }
  rewrite ->Zlength_map; intros.
  unfold hashtable_entry.
  erewrite Znth_map, Znth_upto by (auto; rewrite ->Zlength_upto in *; omega).
  destruct (eq_dec j i).
  - subst; rewrite ->!upd_Znth_same by (rewrite ?Zlength_map; auto; omega).
    rewrite ->prop_true_andp; eauto.
  - rewrite ->!upd_Znth_diff' by (rewrite ?Zlength_map; auto; rewrite ->?Zlength_upto, ?Z2Nat.id; omega).
    erewrite Znth_map, Znth_upto by (auto; rewrite ->Zlength_upto in *; omega); auto.
Qed.

Lemma value_of_inj : forall m v v', value_of m v -> value_of m v' -> v = v'.
Proof.
  unfold value_of; intros ??? (? & ?) (? & ?); eapply log_latest_inj; eauto.
Qed.

Lemma iter_sepcon_map' : forall {B} f (l : list B), iter_sepcon f l = iter_sepcon id (map f l).
Proof.
  intros; rewrite <- iter_sepcon_map; auto.
Qed.

Lemma upd_entries_A : forall T lgk lgv entries pk pv i k lv v, Znth i entries = (pk, pv) ->
  Zlength T = size -> 0 <= i < size -> value_of lv v -> (k = 0 -> v = 0) ->
  (v = 0 -> forall j v', lv j = Some v' -> v' = 0) ->
  iter_sepcon (hashtable_entry_A (upd_Znth i T (k, lv)) lgk lgv entries) (upto (Z.to_nat size)) =
  iter_sepcon (hashtable_entry_A T lgk lgv entries) (remove_Znth i (upto (Z.to_nat size))) * (k_state i lgk pk k * v_state i lgv pv lv).
Proof.
  intros.
  rewrite -> iter_sepcon_map'.
  transitivity (iter_sepcon id (upd_Znth i (map (hashtable_entry_A T lgk lgv entries) (upto (Z.to_nat size))) (k_state i lgk pk k * v_state i lgv pv lv))).
  - f_equal.
    apply list_Znth_eq'.
    { rewrite ->upd_Znth_Zlength; rewrite ->!Zlength_map; auto.
      rewrite ->Zlength_upto, Z2Nat.id; auto; omega. }
    rewrite ->Zlength_map; intros.
    unfold hashtable_entry_A.
    erewrite Znth_map, Znth_upto by (auto; rewrite ->Zlength_upto in *; omega).
    destruct (eq_dec j i).
    + subst; rewrite ->H, !upd_Znth_same by (rewrite ?Zlength_map; auto; omega).
      rewrite ->prop_true_andp; eauto.
    + rewrite ->!upd_Znth_diff' by (rewrite ?Zlength_map; auto; rewrite ->?Zlength_upto, ?Z2Nat.id; omega).
      erewrite Znth_map, Znth_upto by (auto; rewrite ->Zlength_upto in *; omega); auto.
  - rewrite -> iter_sepcon_Znth with (i0 := i) by (rewrite upd_Znth_Zlength; rewrite -> Zlength_map, Zlength_upto, Z2Nat.id; omega).
    rewrite -> upd_Znth_same, remove_upd_Znth by (rewrite -> Zlength_map, Zlength_upto, Z2Nat.id; omega).
    rewrite -> iter_sepcon_map' with (f := hashtable_entry_A _ _ _ _), remove_Znth_map, sepcon_comm; auto.
Qed.

Lemma sepcon_hoist_if : forall {A} {A_eq : EqDec A} (b c : A) P1 P2 Q,
  (if eq_dec b c then P1 * Q else P2 * Q) = Q * if eq_dec b c then P1 else P2.
Proof.
  intros; if_tac; apply sepcon_comm.
Qed.

(* Why isn't this automatic? *)
Instance zero_ord_preorder : PreOrder zero_ord := ord_preorder(P := zero_RA).

Instance table_incl_preorder : RelationClasses.PreOrder table_incl.
Proof.
  split.
  - repeat intro; split; reflexivity.
  - intros ??? Hincl1 Hincl2 ?.
    destruct (Hincl1 i), (Hincl2 i).
    split; etransitivity; eauto.
Qed.

Lemma table_incl_upd : forall T i k v, 0 <= i < Zlength T -> zero_ord (fst (Znth i T)) k ->
  map_incl (snd (Znth i T)) v -> table_incl T (upd_Znth i T (k, v)).
Proof.
  repeat intro.
  destruct (eq_dec i0 i).
  - subst; rewrite ->upd_Znth_same; auto.
  - rewrite ->upd_Znth_diff' by auto; split; reflexivity.
Qed.

Lemma HT_upd_exists : forall H k v (HH : match H k with Some lv => exists v, value_of lv v | None => True end),
  exists H', HT_upd H k v H'.
Proof.
  intros; unfold HT_upd.
  destruct (H k) as [lv|] eqn: Hk.
  - destruct HH as (v0 & j & ? & Hj).
    destruct (log_latest_upd lv j v0 (j + 1) v); unfold log_latest; auto; try omega.
    do 3 eexists; eauto; split; eauto.
    eexists; eauto.
  - eexists _, (ghosts.singleton O v); split; auto; split; auto.
    eexists; apply log_latest_singleton.
Qed.

Lemma zero_ord_0_inv : forall z, zero_ord z 0 -> z = 0.
Proof.
  intros ? [|]; auto.
Qed.

Notation empty := (@empty coPset _).
Notation top := (@top coPset _).

Lemma body_get_item : semax_body Vprog Gprog f_get_item get_item_spec.
Proof.
  start_function.
  unfold atomic_shift; Intros P.
  set (AS := _ -* _).
  forward_call k.
  pose proof size_pos.
  forward_loop (@exp (environ -> mpred) _ _ (fun i => @exp (environ -> mpred) _ _ (fun i1 => @exp (environ -> mpred) _ _ (fun T =>
    PROP (i1 mod size = (i + hash k) mod size; 0 <= i < size; Zlength T = size; table_incl T0 T;
          Forall (fun z => z <> 0 /\ z <> k) (sublist 0 i (rebase (map fst T) (hash k))))
    LOCAL (temp _idx (vint i1); temp _key (vint k); gvars gv)
    SEP (|> P; AS && cored; @data_at CompSpecs sh (tarray tentry size) entries (gv _m_entries); hashtable_A T lgk lgv entries;
         iter_sepcon (fun i => ghost_snap (Znth ((i + hash k) mod size) (map fst T))
           (Znth ((i + hash k) mod size) lgk)) (upto (Z.to_nat i)))))))
    continue: (@exp (environ -> mpred) _ _ (fun i => @exp (environ -> mpred) _ _ (fun i1 => @exp (environ -> mpred) _ _ (fun T =>
        PROP (0 <= i1 <= size; i1 mod size = (i + hash k) mod size; 0 <= i < size; Zlength T = size; table_incl T0 T;
          Forall (fun z => z <> 0 /\ z <> k) (sublist 0 (i + 1) (rebase (map fst T) (hash k))))
        LOCAL (temp _idx (vint i1); temp _key (vint k); gvars gv)
        SEP (AS && cored; |> P; @data_at CompSpecs sh (tarray tentry size) entries (gv _m_entries); hashtable_A T lgk lgv entries;
             iter_sepcon (fun i => ghost_snap (Znth ((i + hash k) mod size) (map fst T))
               (Znth ((i + hash k) mod size) lgk)) (upto (Z.to_nat (i + 1)))))))).
  { Exists 0 (k * 654435761)%Z T0; rewrite ->sublist_nil; entailer!; try apply derives_refl.
    apply hash_size. }
  Intros i i1 T; forward.
  rewrite -> sub_repr, and_repr; simpl.
  rewrite -> Zland_two_p with (n := 14) by omega.
  replace (2 ^ 14) with size by (setoid_rewrite (proj2_sig has_size); auto).
  exploit (Z_mod_lt i1 size); [omega | intro Hi1].
  assert_PROP (Zlength entries = size) as Hentries by entailer!.
  assert (0 <= i1 mod size < Zlength entries) as Hi1' by omega.
  match goal with H : Forall _ _ |- _ => pose proof (Forall_Znth _ _ _ Hi1' H) as Hptr end.
  destruct (Znth (i1 mod size) entries) as (pki, pvi) eqn: Hpi; destruct Hptr.
  forward; setoid_rewrite Hpi.
  { entailer!. }
  assert (0 <= i1 mod size < Zlength (upto (Z.to_nat size))).
  { rewrite ->Zlength_upto, Z2Nat.id; auto; omega. }
  unfold hashtable_A; rewrite -> iter_sepcon_Znth with (i0 := i1 mod size) by auto.
  rewrite -> Znth_upto by (rewrite ->Zlength_upto in *; omega).
  unfold hashtable_entry_A at 1; rewrite -> Hpi.
  destruct (Znth (i1 mod size) T) as (ki, lvi) eqn: HTi; Intros.
  assert (Zlength (rebase (map fst T) (hash k)) = size) as Hrebase.
  { rewrite ->Zlength_rebase; rewrite ->Zlength_map; auto; replace (Zlength T) with size; apply hash_range. }
  (* This is actually a bit tricky: if we load a 0, then this is the linearization point. *)
  forward_call [Z : Type] funspec_sub_refl (pki, ki, zero_ord, k_T' (Znth (i1 mod size) lgk), top,
    fun s v => !!(s = v) && if eq_dec v 0 then Q (0, lvi)
      else |> P * (AS && cored) * k_state (i1 mod size) lgk pki v * ghost_snap v (Znth (i1 mod size) lgk) *
        iter_sepcon (fun i => ghost_snap (Znth ((i + hash k) mod size) (map fst T))
          (Znth ((i + hash k) mod size) lgk)) (upto (Z.to_nat i)) *
          data_at sh (tarray tentry size) entries (gv _m_entries) * v_state (i1 mod size) lgv pvi lvi *
      iter_sepcon (hashtable_entry_A T lgk lgv entries) (remove_Znth (i1 mod size) (upto (Z.to_nat size))), inv_names).
  { unfold Frame; instantiate (1 := []); simpl; rewrite sepcon_emp.
    iIntros "(((((P & AS) & ?) & ?) & ?) & snaps)" (s' Hs' v) "[[% snap] ki]".
    subst; rewrite ->prop_true_andp by auto.
    if_tac; [|iFrame; auto].
    subst; exploit zero_ord_0_inv; eauto; intro; subst.
    match goal with H : exists v, _ |- _ => destruct H as (? & ? & Hz & ?) end.
    specialize (Hz eq_refl); subst.
    iDestruct "AS" as "[AS _]".
    iMod ("AS" with "P") as (HT) "[hashtable [_ HQ]]".
    iMod (own_dealloc(RA := snap_PCM) with "snap") as "_".
    iMod (own_list_dealloc(RA := snap_PCM) with "snaps") as "_".
    { intros; do 3 eexists; apply derives_refl. }
    iApply "HQ"; iFrame.
    iExists T; iSplitR ""; auto.
    iSplit.
    { iPureIntro; split; auto; split; auto.
      exists (i1 mod size); rewrite HTi; split; auto.
      apply lookup'_succeeds with (i := i); rewrite ->?HTi; auto.
      match goal with H : Forall _ (sublist _ _ _) |- _ => rewrite ->rebase_map, sublist_map, Forall_map in H end.
      eapply Forall_impl; eauto; simpl; auto. }
    unfold hashtable_A; rewrite -> iter_sepcon_Znth with (i0 := i1 mod size)(l := upto (Z.to_nat size)) by auto; iFrame.
    erewrite Znth_upto by (rewrite -> ?Zlength_upto, Z2Nat.id; omega).
    unfold hashtable_entry_A; rewrite -> Hpi, HTi; iFrame.
    iSplit; eauto. }
  Intros x; destruct x as (k1, ?); simpl fst in *; simpl snd in *; subst.
  pose proof (hash_range k).
  forward_if (k1 <> k).
  + subst; if_tac; [contradiction | Intros].
    forward; setoid_rewrite Hpi.
    { entailer!. }
    forward_call [(nat -> option Z) : Type] funspec_sub_refl (pvi, lvi, @map_incl nat Z, v_T' (Znth (i1 mod size) lgv), top,
      fun s v => !!(value_of s v /\ (v = 0 -> forall j v', s j = Some v' -> v' = 0)) && Q (v, s), inv_names).
    { subst Frame; instantiate (1 := nil); simpl; cancel.
      iIntros "((((((P & [AS _]) & ?) & snapk) & snaps) & ?) & ?)" (s' Hs' v) "[[% snapv] vi]".
      iMod ("AS" with "P") as (HT) "[hashtable [_ HQ]]".
      rewrite ->prop_true_andp by auto.
      match goal with H : value_of _ _ /\ _ |- _ => destruct H end.
      iAssert (!!(v <> 0 -> exists lv' : _ -> option Z, HT k = Some lv' /\ map_incl s' lv')) as %?.
      { unfold hashtable.
        iDestruct "hashtable" as (T1) "(((% & % & %) & ?) & entries)".
        rewrite -> iter_sepcon_Znth with (i0 := i1 mod size)(l := upto (Z.to_nat size)) by auto.
        erewrite Znth_upto by (rewrite -> ?Zlength_upto, Z2Nat.id; omega).
        unfold hashtable_entry.
        destruct (Znth (i1 mod size) T1) as (?, lvi') eqn: HT1.
        iDestruct "entries" as "(((% & masterk) & masterv) & ?)".
        iCombine "snapk masterk" as "k"; setoid_rewrite snap_master_join; auto; iDestruct "k" as "[% _]".
        iCombine "snapv masterv" as "v"; setoid_rewrite snap_master_join; auto; iDestruct "v" as "[% _]".
        iPureIntro; intros.
        exists lvi'; split; auto.
        match goal with H : forall _ _, _ <-> _ |- _ => rewrite ->H end.
        match goal with H : zero_ord k _ |- _ => destruct H; [contradiction | subst] end.
        split; [rewrite <- HT1; apply Znth_In; omega|].
        match goal with H : exists v, _ /\ _ |- _ => destruct H as (? & ? & ? & Hz) end.
        match goal with H : value_of s' v |- _ => destruct H as (? & ? & ?) end.
        do 2 eexists; eauto. }
      iMod (own_dealloc(RA := snap_PCM) with "snapk") as "_".
      iMod (own_dealloc(RA := snap_PCM(ORD := fmap_order)) with "snapv") as "_".
      iMod (own_list_dealloc(RA := snap_PCM) with "snaps") as "_".
      { intros; do 3 eexists; apply derives_refl. }
      iApply "HQ".
      simpl; iFrame.
      iExists (upd_Znth (i1 mod size) T (k, s')); iSplitR ""; auto; iSplit.
      { iPureIntro; split; [etransitivity; eauto; apply table_incl_upd; rewrite ->?HTi; auto; try omega; etransitivity; eauto|].
        assert (Zlength (upd_Znth (i1 mod size) T (k, s')) = size) by (rewrite upd_Znth_Zlength; auto; omega).
        split; auto.
        exists (i1 mod size); split; [|rewrite upd_Znth_same; auto; omega].
        apply lookup'_succeeds with (i := i); auto; [|rewrite upd_Znth_same; auto; omega].
        replace (i1 mod size) with ((i + hash k) mod size); replace size with (Zlength T).
        rewrite ->rebase_upd', sublist_upd_Znth_l by (rewrite ?Zlength_rebase; omega).
        match goal with H : Forall _ (sublist _ _ _) |- _ => rewrite ->rebase_map, sublist_map, Forall_map in H end.
        eapply Forall_impl; eauto; simpl; auto. }
      unfold hashtable_A; erewrite upd_entries_A; try iFrame; eauto; contradiction. }
    Intros x; destruct x as (v, lvi').
    (* forward_return doesn't play well with atomic specs, but the following line fixes it. *)
    unfold POSTCONDITION, abbreviate; simpl map.
    forward.
    Exists (v, lvi'); entailer!.
  + forward.
    entailer!.
  + Intros; forward_if (k1 <> 0).
    * subst; simpl.
      unfold POSTCONDITION, abbreviate; simpl map.
      forward.
      Exists (0, lvi); entailer!.
    * if_tac; [contradiction|].
      forward.
      entailer!.
    * Intros; rewrite ->if_false by auto.
      Intros; Exists i (i1 mod size) (upd_Znth (i1 mod size) T (k1, lvi)).
      match goal with H : exists v, _ |- _ => destruct H as (? & ? & ? & ?) end.
      unfold hashtable_A; erewrite upd_entries_A by (eauto; contradiction).
      rewrite ->Z2Nat.inj_add, upto_app, iter_sepcon_app by omega.
      change (upto (Z.to_nat 1)) with [0]; simpl iter_sepcon; rewrite ->Z2Nat.id, Z.add_0_r by omega.
      replace ((i + hash k) mod size) with (i1 mod size); rewrite <- upd_Znth_map, upd_Znth_same by (rewrite Zlength_map; omega).
      rewrite ->upd_Znth_map; entailer!.
      { rewrite ->Zmod_mod; split; auto.
        assert (Zlength (upd_Znth (i1 mod size) T (k1, lvi)) = size) by (rewrite upd_Znth_Zlength; auto; omega).
        split; auto.
        split; [etransitivity; eauto; apply table_incl_upd; rewrite ->?HTi; try omega; try reflexivity; auto|].
        replace (i1 mod size) with ((i + hash k) mod size).
        rewrite <- upd_Znth_map.
        replace size with (Zlength (map fst T)) by (rewrite Zlength_map; auto).
        rewrite ->rebase_upd' by (rewrite Zlength_map; auto; omega).
        rewrite ->sublist_upd_Znth_lr by (try omega; setoid_rewrite Hrebase; omega).
        rewrite ->sublist_split with (mid := i), sublist_len_1 by (try omega; setoid_rewrite Hrebase; omega).
        rewrite ->Z.sub_0_r, upd_Znth_app2, Forall_app; rewrite ->Zlength_sublist;
          rewrite ->?Zlength_cons, ?Zlength_nil; try omega; try (setoid_rewrite Hrebase; omega).
        split; auto.
        rewrite ->Z.sub_0_r, Zminus_diag, upd_Znth0, Zlength_cons, sublist_1_cons, sublist_same by (auto; omega).
        repeat constructor; auto; tauto. }
      cancel.
      apply derives_refl', iter_sepcon_func_strong; intros.
      rewrite <- upd_Znth_map, upd_Znth_diff'; auto; rewrite ->?Zlength_map; try omega.
      replace (i1 mod size) with ((i + hash k) mod size); intro X; apply Zmod_plus_inv in X; auto.
      rewrite ->In_upto, Z2Nat.id in * by omega.
      rewrite ->!Zmod_small in X; omega.
  + Intros i i1 keys.
    forward.
    { entailer!.
      rewrite ->!Int.signed_repr; try computable; split; pose proof Int.min_signed_neg; try omega;
        transitivity (size + 1); try omega; setoid_rewrite (proj2_sig has_size); computable. }
    Exists (i + 1) (i1 + 1) keys; entailer!.
    split.
    { rewrite <- Zplus_mod_idemp_l.
      replace (i1 mod _) with ((i + hash k) mod size); simpl.
      rewrite ->Zplus_mod_idemp_l, <- Z.add_assoc, (Z.add_comm _ 1), Z.add_assoc; auto. }
    admit. (* list is long enough *)
Admitted.

Lemma body_add_item : semax_body Vprog Gprog f_add_item add_item_spec.
Proof.
  start_function.
  unfold atomic_shift; Intros P.
  set (AS := _ -* _).
  forward_call k.
  pose proof size_pos.
  forward_loop (EX i : Z, EX i1 : Z, EX T : list (Z * (_ -> option Z)),
    PROP (i1 mod size = (i + hash k) mod size; 0 <= i < size; Zlength T = size; table_incl T0 T;
          Forall (fun z => z <> 0 /\ z <> k) (sublist 0 i (rebase (map fst T) (hash k))))
    LOCAL (temp _idx (vint i1); temp _key (vint k); temp _value (vint v); gvars gv)
    SEP (AS && cored; |> P; @data_at CompSpecs sh (tarray tentry size) entries (gv _m_entries); hashtable_A T lgk lgv entries;
         iter_sepcon (fun i => ghost_snap(ORD := zero_order) (Znth ((i + hash k) mod size) (map fst T))
           (Znth ((i + hash k) mod size) lgk)) (upto (Z.to_nat i))))
    continue: (EX i : Z, EX i1 : Z, EX T : list (Z * (_ -> option Z)),
    PROP (i1 mod size = (i + hash k) mod size; 0 <= i < size; Zlength T = size; table_incl T0 T;
          Forall (fun z => z <> 0 /\ z <> k) (sublist 0 (i + 1) (rebase (map fst T) (hash k))))
    LOCAL (temp _idx (vint i1); temp _key (vint k); temp _value (vint v); gvars gv)
    SEP (AS && cored; |> P; @data_at CompSpecs sh (tarray tentry size) entries (gv _m_entries); hashtable_A T lgk lgv entries;
         iter_sepcon (fun i => ghost_snap(ORD := zero_order) (Znth ((i + hash k) mod size) (map fst T))
           (Znth ((i + hash k) mod size) lgk)) (upto (Z.to_nat (i + 1))))).
  { Exists 0 (k * 654435761)%Z T0; rewrite ->sublist_nil; entailer!.
    apply hash_size. change (upto (Z.to_nat 0)) with (@nil Z); simpl; auto. }
  - Intros i i1 T; forward.
    rewrite ->sub_repr, and_repr; simpl.
    rewrite ->Zland_two_p with (n := 14) by omega.
    replace (2 ^ 14) with size by (setoid_rewrite (proj2_sig has_size); auto).
    exploit (Z_mod_lt i1 size); [omega | intro Hi1].
    assert_PROP (Zlength entries = size) as Hentries by entailer!.
    assert (0 <= i1 mod size < Zlength entries) as Hi1' by omega.
    match goal with H : Forall _ _ |- _ => pose proof (Forall_Znth _ _ _ Hi1' H) as Hptr end.
    destruct (Znth (i1 mod size) entries) as (pki, pvi) eqn: Hpi; destruct Hptr.
    forward; setoid_rewrite Hpi.
    { entailer!. }
    assert (0 <= i1 mod size < Zlength (upto (Z.to_nat size))).
    { rewrite ->Zlength_upto, Z2Nat.id; auto; omega. }
    unfold hashtable_A; rewrite -> iter_sepcon_Znth with (i0 := i1 mod size) by auto.
    rewrite -> Znth_upto by (auto; rewrite ->Zlength_upto in *; omega).
    assert (Zlength (rebase (map fst T) (hash k)) = size) as Hrebase.
    { rewrite ->Zlength_rebase; rewrite ->Zlength_map; replace (Zlength T) with size; auto; apply hash_range. }
    unfold hashtable_entry_A at 1; rewrite ->Hpi.
    destruct (Znth (i1 mod size) T) as (ki, lvi) eqn: HTi; Intros.
    forward_call [Z : Type] funspec_sub_refl (pki, ki, zero_ord, k_T' (Znth (i1 mod size) lgk), top,
      fun s v => k_T Share.bot (Znth (i1 mod size) lgk) s v * k_state (i1 mod size) lgk pki s, inv_names).
    { rewrite <- emp_sepcon at 1; apply sepcon_derives; [|cancel].
      iIntros "_" (s' Hs' v0) "$"; auto. }
    unfold k_T at 1; Intros x; destruct x as (k1, ?); simpl fst in *; simpl snd in *; subst.
    pose proof (hash_range k).
    assert (forall x, Zlength (upd_Znth (i1 mod size) T x) = size).
    { intro; rewrite ->upd_Znth_Zlength; auto; omega. }
    gather_SEP 0 1 3.
    match goal with |- semax _ (PROP () (LOCALx (_ :: ?Q) (SEPx (_ :: ?R)))) _ _ =>
      forward_if (PROP (zero_ord k1 k) (LOCALx Q (SEPx (k_state (i1 mod size) lgk pki k ::
        ghost_snap k (Znth (i1 mod size) lgk) :: |> P :: R)))) end.
    + assert (forall k1 v, (k1 <> k /\ k1 <> 0) ->
        Forall (fun z => z <> 0 /\ z <> k)
          (sublist 0 (i + 1) (rebase (map fst (upd_Znth (i1 mod size) T (k1, v))) (hash k)))).
      { intros; replace (i1 mod size) with ((i + hash k) mod size).
        replace size with (Zlength (map fst T)) by (rewrite Zlength_map; auto).
        rewrite <- upd_Znth_map, rebase_upd' by (rewrite Zlength_map; auto; omega).
        rewrite ->sublist_upd_Znth_lr by (try omega; setoid_rewrite Hrebase; omega).
        rewrite ->sublist_split with (mid := i), sublist_len_1 by (try omega; setoid_rewrite Hrebase; omega).
        rewrite ->Z.sub_0_r, upd_Znth_app2, Forall_app; rewrite ->Zlength_sublist;
          rewrite ->?Zlength_cons, ?Zlength_nil; try omega; try (setoid_rewrite Hrebase; omega).
        split; auto.
        rewrite ->Z.sub_0_r, Zminus_diag, upd_Znth0, Zlength_cons, sublist_1_cons, sublist_same
          by (auto; omega).
        repeat constructor; auto; tauto. }
      forward_if (k1 = 0).
      { forward.
        Exists i (i1 mod size) (upd_Znth (i1 mod size) T (k1, snd (Znth (i1 mod size) T))); rewrite ->Zmod_mod, Z2Nat.inj_add, upto_app, iter_sepcon_app by omega.
        change (upto (Z.to_nat 1)) with [0]; simpl iter_sepcon.
        rewrite ->Z2Nat.id, Z.add_0_r by omega.
        replace ((i + hash k) mod size) with (i1 mod size).
        rewrite ->Znth_map, upd_Znth_same; try omega.
        Intros.
        match goal with H : exists v, _ |- _ => destruct H as (? & ? & ? & ?) end.
        unfold hashtable_A; erewrite upd_entries_A by (eauto; rewrite ->?HTi; eauto; contradiction).
        rewrite ->HTi; entailer!.
        { etransitivity; eauto; apply table_incl_upd; rewrite ->?HTi; auto; try omega; reflexivity. }
        cancel.
        rewrite sepcon_comm; apply sepcon_derives, derives_refl.
        apply derives_refl', iter_sepcon_func_strong; intros.
        rewrite <- upd_Znth_map, upd_Znth_diff'; auto; rewrite ->?Zlength_map; try omega.
        replace (i1 mod size) with ((i + hash k) mod size); intro X; apply Zmod_plus_inv in X; auto.
        rewrite ->In_upto, Z2Nat.id in * by omega.
        rewrite ->!Zmod_small in X; omega.
        { rewrite ->upd_Znth_Zlength; omega. } }
      { forward.
        entailer!. }
      Intros; subst.
      forward_call [Z : Type] funspec_sub_refl (pki, 0, k, 0, zero_ord, k_T' (Znth (i1 mod size) lgk), top,
        fun s => AS && cored * |> P * (!!(s = k) && k_state (i1 mod size) lgk pki s *
          ghost_snap s (Znth (i1 mod size) lgk) *
          iter_sepcon (fun i => ghost_snap (Znth ((i + hash k) mod size) (map fst T))
            (Znth ((i + hash k) mod size) lgk)) (upto (Z.to_nat i))),
        fun s v => |> (AS && cored * P * (!!(s = v) && k_state (i1 mod size) lgk pki s *
          ghost_snap s (Znth (i1 mod size) lgk) *
          iter_sepcon (fun i => ghost_snap (Znth ((i + hash k) mod size) (map fst T))
            (Znth ((i + hash k) mod size) lgk)) (upto (Z.to_nat i)))), inv_names).
      { subst Frame; instantiate (1 := [data_at _ (tarray tentry _) entries _; v_state (i1 `mod` size) lgv pvi lvi;
          iter_sepcon (hashtable_entry_A T lgk lgv entries) (remove_Znth (i1 mod size) (upto (Z.to_nat size)))]); simpl; cancel.
        iIntros "(((snap & P) & AS) & snaps)"; iSplit.
        * iIntros (s' Hs') "[% master2]".
          iDestruct (cored_dup with "AS") as "[AS ?]".
          iMod ("AS" with "P") as (HT) "[hashtable [HP _]]".
          unfold hashtable; iDestruct "hashtable" as (T1) "((% & excl) & entries)".
          match goal with H : _ /\ _ /\ _ |- _ => destruct H as (? & ? & ?) end.
          rewrite -> iter_sepcon_Znth with (i0 := i1 mod size)(l := upto (Z.to_nat size)) by auto.
          erewrite Znth_upto by (rewrite -> ?Zlength_upto, Z2Nat.id; omega).
          unfold hashtable_entry at 1.
          destruct (Znth (i1 mod size) T1) as (?, lvi') eqn: HT1.
          iDestruct "entries" as "(((% & master) & masterv) & entries)".
          iCombine "master master2" as "master"; erewrite (master_share_join'(ORD := zero_order)) by eauto; iDestruct "master" as "[% master]".
          iAssert (!!(lookup' T1 k = Some (i1 mod size))) as %Hindex.
          { iApply (entries_lookup with "[$entries $snaps]"); auto.
            { rewrite -> Zlength_map; auto. }
            { rewrite -> HT1; auto. } }
          iMod (own_dealloc(RA := snap_PCM) with "snap") as "_".
          iMod (master_update(ORD := zero_order) _ k with "master") as "master"; first auto.
          erewrite <- (master_share_join(ORD := zero_order)) by eauto; iDestruct "master" as "[master master2]".
          subst; match goal with H : exists v, _ /\ _ |- _ => destruct H as (? & ? & Hz & ?);
            specialize (Hz eq_refl); subst end.
          iMod ("HP" with "[$excl master masterv entries]") as "P".
          { iExists (upd_Znth (i1 mod size) T1 (k, lvi')); iSplitL ""; auto.
            { iSplit; auto; iPureIntro.
              assert (Zlength (upd_Znth (i1 mod size) T1 (k, lvi')) = size)
                by (rewrite upd_Znth_Zlength; auto; omega).
              split; auto.
              split; [apply wf_table_upd; auto|].
              intros.
              etransitivity; eauto; split; intros (Hin & ?); split; auto.
              - eapply In_upd_Znth_old; auto; try omega.
                intro X; rewrite <- X in HT1; inv HT1.
                match goal with H : exists v, _ /\ _ |- _ => destruct H as (? & ? & Hnz) end.
                contradiction Hnz; eapply value_of_inj; eauto.
              - apply In_upd_Znth in Hin; destruct Hin as [X|]; auto.
                inv X.
                match goal with H : exists v, _ /\ _ |- _ => destruct H as (? & ? & Hnz) end.
                contradiction Hnz; eapply value_of_inj; eauto. }
            rewrite -> iter_sepcon_Znth with (i0 := i1 mod size)(l := upto _) by auto.
            rewrite -> Znth_upto by (auto; rewrite -> Zlength_upto in *; omega).
            unfold hashtable_entry; rewrite -> upd_Znth_same by omega; iFrame.
            iSplitL ""; [iSplit; eauto|].
            erewrite iter_sepcon_func_strong; [iApply "entries"|].
            intros ??%In_remove_upto; try omega; simpl.
            rewrite -> upd_Znth_diff' by omega; auto. }
          iModIntro; iExists k; iSplit; auto.
          iMod (make_snap with "master2") as "[? ?]".
          iIntros "ki !>"; iFrame.
          iSplitL ""; auto.
        * iIntros (s' v' (? & ? & ?)) "[>[% snap'] ki]".
          iMod (own_dealloc(RA := snap_PCM) with "snap") as "_".
          subst; rewrite -> prop_true_andp by auto; iFrame; auto. }
      Intros x; destruct x as (k1, ?); simpl fst in *; simpl snd in *.
      match goal with |- semax _ (PROP () (LOCALx (_ :: _ :: ?Q) (SEPx (_ :: ?R)))) _ _ =>
        forward_if (PROP (zero_ord k1 k) ((LOCALx Q) (SEPx (AS && cored :: |> P :: k_state (i1 mod size) lgk pki k ::
          ghost_snap k (Znth (i1 mod size) lgk) :: iter_sepcon (fun i0 : Z =>
                 ghost_snap (Znth ((i0 + hash k) mod size) (map fst T))
                   (Znth ((i0 + hash k) mod size) lgk)) (upto (Z.to_nat i)) :: R)))) end.
      * if_tac; [discriminate|].
        forward_call [Z : Type] funspec_sub_refl (pki, k1, zero_ord, k_T' (Znth (i1 mod size) lgk), top,
          fun s v => k_T Share.bot (Znth (i1 mod size) lgk) s v * k_state (i1 mod size) lgk pki s, inv_names).
        { entailer!.
          rewrite <- emp_sepcon at 1; apply sepcon_derives; [|cancel_frame].
          iIntros "_" (???) "[$ $]"; auto. }
        unfold k_T at 1; Intros x; destruct x as (k2, ?); simpl fst in *; simpl snd in *; subst.
        match goal with H : zero_ord k1 k2 |- _ => destruct H; [contradiction | subst k2] end.
        gather_SEP 0 4; setoid_rewrite ghost_snap_join; [|apply join_refl].
        forward_if (k1 = k).
        { forward.
          Exists i (i1 mod size) (upd_Znth (i1 mod size) T (k1, lvi)); rewrite Zmod_mod.
          match goal with H : exists v, _ |- _ => destruct H as (? & ? & ? & ?) end.
          unfold hashtable_A; erewrite upd_entries_A by (eauto; contradiction).
          rewrite -> Z2Nat.inj_add, upto_app, iter_sepcon_app by omega.
          change (upto (Z.to_nat 1)) with [0]; simpl iter_sepcon; rewrite ->Z2Nat.id, Z.add_0_r by omega.
          replace ((i + hash k) mod size) with (i1 mod size); rewrite <- upd_Znth_map, upd_Znth_same by (rewrite Zlength_map; omega).
          rewrite -> upd_Znth_map; entailer!.
          { etransitivity; eauto; apply table_incl_upd; rewrite ->?HTi; try omega; try reflexivity.
            etransitivity; eauto. }
          cancel.
          apply iter_sepcon_derives; intros ??%In_upto.
          rewrite <- upd_Znth_map, upd_Znth_diff'; auto; rewrite ->?Zlength_map; try omega.
          replace (i1 mod size) with ((i + hash k) mod size); intro X; apply Zmod_plus_inv in X; auto.
          rewrite -> Z2Nat.id in * by omega.
          rewrite -> !Zmod_small in X; omega. }
        { forward.
          entailer!. }
        entailer!.
      * forward.
        if_tac; [Intros; subst | discriminate].
        entailer!.
      * entailer!.
    + forward.
      subst; unfold ghost_master, ghost_snap; entailer!.
    + forward; setoid_rewrite Hpi.
      { entailer!. }
      forward_call [(nat -> option Z) : Type] funspec_sub_refl (pvi, 0, v, lvi, @map_incl nat Z, v_T' (Znth (i1 mod size) lgv), top,
        fun s'' => Q (true, s''),
        fun s' (v' : Z) => Q (false, s'), inv_names).
      { subst Frame; instantiate (1 := []); simpl; cancel.
        iIntros "((((((ki & snap) & P) & [AS _]) & data) & entries_A) & snaps)"; iSplit.
        * iIntros (s' Hs') "[% master] !>".
          match goal with H : value_of s' 0 /\ _ |- _ => destruct H as ((j & Hlv) & ?) end.
          destruct (log_latest_upd s' j 0 (j + 1) v); auto; try omega.
          iExists (map_upd s' (j + 1)%nat v); rewrite -> prop_true_andp by auto.
          iIntros "vi".
          iMod ("AS" with "P") as (H') "[hashtable [_ HQ]]".
          unfold hashtable; iDestruct "hashtable" as (T1) "((% & excl) & entries)".
          match goal with H : _ /\ _ /\ _ |- _ => destruct H as (? & ? & ?) end.
          rewrite -> iter_sepcon_Znth with (i0 := i1 mod size)(l := upto (Z.to_nat size)) by auto.
          erewrite Znth_upto by (rewrite -> ?Zlength_upto, Z2Nat.id; omega).
          unfold hashtable_entry at 1.
          destruct (Znth (i1 mod size) T1) as (?, lvi') eqn: HT1.
          iDestruct "entries" as "(((% & masterk) & masterv) & entries)".
          iCombine "snap masterk" as "masterk"; rewrite -> snap_master_join by auto.
          iDestruct "masterk" as "[% masterk]".
          match goal with H : zero_ord k _ |- _ => destruct H; [contradiction | subst z] end.
          iCombine "masterv master" as "master"; erewrite (master_share_join'(ORD := fmap_order)) by eauto; iDestruct "master" as "[% master]".
          iMod (master_update(ORD := fmap_order) s' (map_upd s' (j + 1)%nat v) with "master") as "master"; auto.
          erewrite <- (master_share_join(ORD := fmap_order)) by eauto.
          iDestruct "master" as "[?$]".
          iMod (exclusive_update H' (map_upd H' k (map_upd s' (j + 1)%nat v)) with "excl").
          assert (value_of (map_upd s' (j + 1)%nat v) v) by (eexists; eauto).
          iAssert (!!(lookup' T1 k = Some (i1 mod size))) as %PP.
          { iApply (entries_lookup with "[$entries $snaps]"); auto.
            { rewrite -> Zlength_map; auto. }
            { rewrite -> HT1; auto. } }
          iMod (own_list_dealloc(RA := snap_PCM) with "snaps") as "_".
          { intro; do 3 eexists; apply derives_refl. }
          iMod ("HQ" with "[-]") as "$"; auto.
          simpl; iFrame.
          iExists (upd_Znth (i1 mod size) T (k, map_upd s' (j + 1)%nat v)).
          assert (Zlength (upd_Znth (i1 mod size) T1 (k, map_upd s' (j + 1)%nat v)) = size)
                by (rewrite upd_Znth_Zlength; auto; omega).
          iSplitL "ki vi entries_A".
          -- iSplit.
             { iPureIntro.
               split; [etransitivity; eauto; apply table_incl_upd; rewrite ->?HTi; auto; try omega; etransitivity; eauto|].
               split; auto.
               exists (i1 mod size); split; [|rewrite upd_Znth_same; auto; omega].
               apply lookup'_succeeds with (i := i); auto; [|rewrite upd_Znth_same; auto; omega].
               replace (i1 mod size) with ((i + hash k) mod size); replace size with (Zlength T).
               rewrite ->rebase_upd', sublist_upd_Znth_l by (rewrite ?Zlength_rebase; omega).
               match goal with H : Forall _ (sublist _ _ _) |- _ => rewrite ->rebase_map, sublist_map, Forall_map in H end.
               eapply Forall_impl; eauto; simpl; auto. }
             match goal with H : exists v, _ |- _ => destruct H as (? & ? & ? & ?) end.
             unfold hashtable_A; erewrite upd_entries_A by (eauto; contradiction); iFrame.
          -- iSplit.
             { iPureIntro.
               destruct (H' k) eqn: Hk; [|tauto].
               match goal with H : forall _ _, _ <-> _ |- _ => rewrite ->H in Hk end.
               destruct Hk as (Hk & ? & ? & Hnz).
               eapply In_Znth in Hk; destruct Hk as (i' & ? & Hk).
               match goal with H : wf_table T1 |- _ => exploit (H k i'); rewrite ->?Hk; auto end.
               intro X; rewrite ->X in PP; inv PP.
               rewrite ->Hk in HT1; inv HT1.
               contradiction Hnz; eapply value_of_inj; eauto; eexists; eauto. }
             iExists (upd_Znth (i1 mod size) T1 (k, map_upd s' (j + 1)%nat v)).
             iSplitL "".
             { iSplit; auto; iPureIntro.
               assert (Zlength (upd_Znth (i1 mod size) T1 (k, map_upd s' (j + 1)%nat v)) = size)
                 by (rewrite upd_Znth_Zlength; auto; omega).
               split; auto.
               split; [apply wf_table_upd; auto|].
               unfold map_upd at 1.
               intro k0; if_tac.
               * split; [intro X; inv X; split; eauto; apply upd_Znth_In|].
                 subst; intros (Hin & ?).
                 apply In_Znth in Hin; destruct Hin as (i' & Hi' & Hith).
                 destruct (eq_dec i' (i1 mod size)).
                 { subst; rewrite ->upd_Znth_same in Hith by omega; inv Hith; auto. }
                 rewrite ->upd_Znth_diff' in Hith by (auto; omega).
                 match goal with H : wf_table T1 |- _ => exploit (H k i'); rewrite ->?Hith; auto; congruence end.
               * etransitivity; eauto; split; intros (Hin & ?); split; auto.
                 -- eapply In_upd_Znth_old; auto; try omega.
                    intro X; rewrite <- X in HT1; inv HT1; contradiction.
                 -- apply In_upd_Znth in Hin; destruct Hin as [X|]; [inv X; tauto | auto]. }
             erewrite iter_sepcon_map' with (l := upto (Z.to_nat size)), upd_entries by (eauto; contradiction).
             rewrite -> iter_sepcon_Znth with (i0 := i1 mod size)(l := upd_Znth _ _ _).
             rewrite -> remove_upd_Znth, upd_Znth_same by (rewrite Zlength_map; auto).
             rewrite -> iter_sepcon_map', remove_Znth_map; iFrame.
             { rewrite upd_Znth_Zlength; rewrite Zlength_map; omega. }
        * iIntros (s' v' Hs') "[>[% snapv] vi]".
          iMod ("AS" with "P") as (H') "[hashtable [_ HQ]]".
          iMod (own_list_dealloc(RA := snap_PCM) with "snaps") as "_".
          { do 3 eexists; apply derives_refl. }
          iApply "HQ".
          simpl; iFrame "data".
          unfold hashtable; iDestruct "hashtable" as (T1) "((% & excl) & entries)".
          repeat match goal with H : _ /\ _ /\ _ |- _ => destruct H as (? & ? & ?) end.
          rewrite -> iter_sepcon_Znth' with (i0 := (i1 mod size))(l := upto (Z.to_nat size)) by auto.
          rewrite -> Znth_upto by (auto; rewrite ->Z2Nat.id; omega).
          unfold hashtable_entry at 1.
          destruct (Znth (i1 mod size) T1) as (k', lv) eqn: HT1.
          iDestruct "entries" as "(((% & masterk) & masterv) & entries)".
          iCombine "snap masterk" as "master"; rewrite -> snap_master_join by auto.
          iDestruct "master" as "[% master]".
          match goal with H : zero_ord k _ |- _ => destruct H; [contradiction | subst k'] end.
          iCombine "snapv masterv" as "masterv"; setoid_rewrite snap_master_join; auto.
          iDestruct "masterv" as "[% masterv]".
          match goal with H : value_of s' _ /\ _ |- _ => destruct H end.
          iExists (upd_Znth (i1 mod size) T (k, s')); iSplitL "ki vi entries_A".
          -- iSplit.
             { iPureIntro.
               split; [etransitivity; eauto; apply table_incl_upd; rewrite ->?HTi; auto; try omega; etransitivity; eauto|].
               rewrite -> upd_Znth_Zlength by omega; split; auto.
               exists (i1 mod size); split; [|rewrite upd_Znth_same; auto; omega].
               apply lookup'_succeeds with (i := i); auto; [|rewrite upd_Znth_same; auto; omega].
               replace (i1 mod size) with ((i + hash k) mod size); replace size with (Zlength T).
               rewrite ->rebase_upd', sublist_upd_Znth_l by (rewrite ?Zlength_rebase; omega).
               match goal with H : Forall _ (sublist _ _ _) |- _ => rewrite ->rebase_map, sublist_map, Forall_map in H end.
               eapply Forall_impl; eauto; simpl; auto. }
             unfold hashtable_A; erewrite upd_entries_A by (eauto; contradiction); iFrame.
          -- iSplit.
             { iPureIntro.
               assert (H' k = Some lv) as Hk; [|rewrite Hk; repeat split; discriminate].
               match goal with H : forall _ _, _ <-> _ |- _ => rewrite ->H end.
               split; [rewrite <- HT1; apply Znth_In; omega|].
               match goal with H : exists v, _ |- _ => destruct H as (? & ? & ? & Hz) end.
               do 2 eexists; eauto.
               intro X; specialize (Hz X).
               match goal with H : value_of s' _ |- _ => destruct H as (? & ? & ?); eauto end. }
             iExists T1; iFrame.
             iSplitL ""; auto.
             iApply "entries"; unfold hashtable_entry.
             rewrite HT1; iFrame; auto. }
      Intros x; destruct x as (v', lvi').
      unfold POSTCONDITION, abbreviate; simpl map.
      forward.
      Exists (if eq_dec v' 0 then true else false, lvi'); entailer!.
      if_tac; apply derives_refl.
  - Intros i i1 T.
    forward.
    entailer!.
    { admit. } (* list is long enough *)
    Exists (i + 1) (i1 + 1) T; entailer!.
    rewrite <- Zplus_mod_idemp_l.
    replace (i1 mod _) with ((i + hash k) mod size); simpl.
    rewrite ->Zplus_mod_idemp_l, <- Z.add_assoc, (Z.add_comm _ 1), Z.add_assoc; auto.
    { admit. } (* list is long enough *)
Admitted.

Check iter_sepcon_derives.

(* up *)
Lemma iter_sepcon_viewshift: forall {A} `{Inhabitant A} f g (l : list A),
  (forall i, 0 <= i < Zlength l -> f (Znth i l) |-- |==> g (Znth i l))%I ->
  (iter_sepcon f l |-- |==> iter_sepcon g l)%I.
Proof.
  induction l; simpl; intros.
  - apply bupd_intro.
  - rewrite Zlength_cons in H0.
    iIntros "[f ?]"; iSplitL "f".
    + specialize (H0 0); rewrite ->!Znth_0_cons in H0; iApply H0; auto; rep_omega.
    + iApply IHl; try omega; auto; intros.
      specialize (H0 (i + 1)); rewrite ->!Znth_pos_cons, !Z.add_simpl_r in H0 by omega; apply H0; rep_omega.
Qed.

Opaque Znth.

(* up *)
Lemma Znth_repeat_gen : forall {A} {X : Inhabitant A} (x : A) n i,
  Znth i (repeat x n) = x \/ Znth i (repeat x n) = default.
Proof.
  induction n; simpl; intros.
  - rewrite ->Znth_nil; auto.
  - destruct (zlt i 0); [rewrite Znth_underflow; auto|].
    destruct (eq_dec i 0); [subst; rewrite ->Znth_0_cons; auto|].
    rewrite ->Znth_pos_cons; auto; omega.
Qed.

Lemma body_init_table : semax_body Vprog Gprog f_init_table init_table_spec.
Proof.
  start_function.
  forward_for_simple_bound size (EX i : Z, EX entries : list (val * val),
    PROP (Forall (fun '(pk, pv) => isptr pk /\ isptr pv) entries; Zlength entries = i)
    LOCAL (gvars gv)
    SEP (mem_mgr gv; @data_at CompSpecs Ews (tarray tentry size) (entries ++ repeat (Vundef, Vundef) (Z.to_nat (size - i))) (gv _m_entries);
         iter_sepcon (fun x =>
           malloc_token Ews tint (fst x) * malloc_token Ews tint (snd x)) entries;
         iter_sepcon (fun '(pk, pv) => data_at Ews tint (vint 0) pk) entries;
         iter_sepcon (fun '(pk, pv) => data_at Ews tint (vint 0) pv) entries)).
  { setoid_rewrite (proj2_sig has_size); computable. }
  { setoid_rewrite (proj2_sig has_size); computable. }
  { setoid_rewrite (proj2_sig has_size); computable. }
 - Exists (@nil (val * val)); entailer!.
    rewrite ->data_at__eq; unfold default_val; simpl.
    rewrite ->repeat_list_repeat; apply derives_refl.
  - rewrite -> iter_sepcon_sepcon'.
    forward_call (tint, gv).
    { split; auto; simpl; computable. }
    Intros pk.
    repeat forward.
    forward_call (tint, gv).
    { split; auto; simpl; computable. }
    Intros pv.
    repeat forward.
    assert (0 <= i < Zlength (entries ++ repeat (Vundef, Vundef) (Z.to_nat (size - i)))).
    { rewrite ->Zlength_app, Zlength_repeat, Z2Nat.id; omega. }
    rewrite ->upd_Znth_twice, upd_Znth_same by auto.
    go_lower; Exists (entries ++ [(pk, pv)]).
    rewrite -> !iter_sepcon_app, upd_init, <- app_assoc, iter_sepcon_sepcon' by (auto; omega).
    rewrite ->Zlength_app, Zlength_cons, Zlength_nil; simpl; entailer!; auto.
    rewrite ->Forall_app; repeat constructor; auto.
  - Intros entries.
    rewrite ->Zminus_diag, app_nil_r.
    pose proof size_pos.
    ghosts_alloc (ghost_master Tsh 0) size; [omega|].
    Intros lgk.
    ghosts_alloc (ghost_master(ORD := fmap_order) Tsh (ghosts.singleton O 0)) size; [omega|].
    Intros lgv.
    ghost_alloc (fun g => excl(A := (Z -> option (nat -> option Z))) g (fun _ => None)).
    Intros g.
    gather_SEP (excl _ _) (iter_sepcon _ _) (iter_sepcon _ _)
      (iter_sepcon (fun '(pk, _) => _) entries) (iter_sepcon (fun '(_, pv) => _) entries).
    viewshift_SEP 0 (hashtable (fun _ => None) g lgk lgv * hashtable_A (repeat (0, ghosts.singleton O 0) (Z.to_nat size)) lgk lgv entries).
    { go_lower.
      setoid_rewrite (list_Znth_eq entries) at 1 2.
      rewrite ->(list_Znth_eq lgk) at 1.
      rewrite ->(list_Znth_eq lgv) at 1.
      rewrite ->Zlength_correct in *.
      replace (length entries) with (Z.to_nat size) by rep_omega.
      replace (length lgk) with (Z.to_nat size) by rep_omega.
      replace (length lgv) with (Z.to_nat size) by rep_omega.
      rewrite ->!sepcon_assoc, sepcon_comm, <- !sepcon_assoc.
      rewrite <- !iter_sepcon_map, <- !iter_sepcon_sepcon'.
      eapply derives_trans; [apply sepcon_derives, derives_refl;
        apply iter_sepcon_viewshift with (g0 := fun i =>
        hashtable_entry (repeat (0, ghosts.singleton 0%nat 0) (Z.to_nat size)) lgk lgv i * hashtable_entry_A (repeat (0, ghosts.singleton 0%nat 0) (Z.to_nat size)) lgk lgv entries i)|].
      rewrite Zlength_upto; intros; rewrite -> Znth_upto by auto.
      unfold hashtable_entry, hashtable_entry_A.
      rewrite -> Znth_repeat' by auto.
      destruct (Znth i entries).
      erewrite <- (master_share_join(ORD := zero_order)) by eauto.
      erewrite <- (master_share_join) by eauto.
      iIntros "((((masterv1 & masterv2) & (masterk1 & masterk2)) & datak) & datav)".
      iMod (make_protocol with "[$datak masterk2]"); auto.
      { unfold k_T; iFrame; eauto. }
      assert (forall j v', ghosts.singleton O 0 j = Some v' -> v' = 0).
      { intros ??; unfold ghosts.singleton; if_tac; intro X; inv X; auto. }
      iMod (make_protocol _ _ _ (P := v_prot _) with "[$datav masterv2]"); auto.
      { unfold v_T; iFrame; eauto. }
      iFrame.
      iModIntro; iSplitL ""; iSplit; eauto.
      { iIntros "[>H ?] !>".
        rewrite iter_sepcon_sepcon'; unfold hashtable, hashtable_A; iDestruct "H" as "[??]"; iFrame.
        iExists (repeat (0, ghosts.singleton 0%nat 0) (Z.to_nat size)); iFrame.
        iSplit; auto; iPureIntro.
        split; [rewrite Zlength_repeat; rep_omega|].
        split.
        { intros ??? Hk.
          edestruct (Znth_repeat_gen (0, ghosts.singleton O 0)) as [Heq | Heq]; rewrite ->Heq in Hk; simpl in *; subst; contradiction. }
        split; [discriminate|].
        intros [Heq%repeat_spec (? & Hv & ?)]; inv Heq.
        eapply value_of_inj in Hv; [|apply value_of_0]; subst; contradiction. } }
    forward.
    Exists entries g lgk lgv; entailer!.
    erewrite sepcon_comm, iter_sepcon_func; [apply derives_refl | intros (?, ?); reflexivity].
Qed.

Lemma lock_struct_array : forall sh z (v : list val) p,
  data_at sh (tarray (tptr (Tstruct _lock_t noattr)) z) v p =
  data_at sh (tarray (tptr tlock) z) v p.
Proof.
  intros.
  unfold data_at, field_at, at_offset; rewrite ->!data_at_rec_eq; simpl; f_equal.
Admitted.

Lemma f_pred_exclusive : forall N gv tsh sh gsh (entries : list (val * val)) gh g lgk lgv t lockt res inv_names,
  readable_share sh -> Zlength lgk = Zlength entries -> Zlength lgv = Zlength entries ->
  exclusive_mpred (f_lock_pred N gv tsh sh gsh entries gh g lgk lgv t lockt res inv_names).
Proof.
  intros; unfold f_lock_pred.
  apply selflock_exclusive.
  unfold f_lock_inv.
  eapply derives_exclusive with (Q := (EX h : nat -> option hashtable_hist_el, ghost_hist gsh h gh) *
    mem_mgr gv * data_at_ _ _ _ * invariant N (hashtable_inv gh g lgk lgv) *
    (EX T : _, hashtable_A T _ _ _) * data_at_ sh _ _ * data_at_ _ _ _ * data_at_ _ _ _).
  - Intros b1 b2 b3 h.
    repeat (apply sepcon_derives; try apply data_at_data_at_); eauto.
    Exists h; auto.
    apply derives_refl.
  - apply exclusive_sepcon2, data_at__exclusive; auto; simpl; omega.
Qed.
Hint Resolve f_pred_exclusive.

Lemma apply_hist_app : forall h1 h2 H H', apply_hist H (h1 ++ h2) H' <->
  exists H1, apply_hist H h1 H1 /\ apply_hist H1 h2 H'.
Proof.
  induction h1; auto; simpl; intros.
  { split; [|intros (? & ? & ?)]; subst; eauto. }
  destruct a.
  - split.
    + intros (? & ? & H1); rewrite ->IHh1 in H1.
      destruct H1 as (? & ? & ?); eauto.
    + intros (? & (? & ? & ?) & ?); eexists; rewrite ->IHh1; eauto.
  - split.
    + intros (? & H1); rewrite ->IHh1 in H1.
      destruct H1 as (? & ? & ?); eauto.
    + intros (? & (? & ?) & ?); rewrite ->IHh1; eauto.
  - split.
    + destruct r.
      * intros (? & ? & ? & H1); rewrite ->IHh1 in H1.
        destruct H1 as (? & ? & ?); eauto 6.
      * intros (? & H1); rewrite ->IHh1 in H1.
        destruct H1 as (? & ? & ?); eauto.
    + destruct r.
      * intros (? & (? & ? & ? & ?) & ?); split; auto.
        eexists; rewrite ->IHh1; eauto.
      * intros (? & (? & ?) & ?); rewrite ->IHh1; eauto.
Qed.

Lemma body_f : semax_body Vprog Gprog f_f f_spec.
Proof.
  start_function.
  rewrite ->(data_at_isptr Ews); Intros.
  forward.
  rewrite <- lock_struct_array.
  forward.
  { entailer!.
    rewrite ->upd_Znth_same; auto. }
  forward.
  { entailer!.
    rewrite ->upd_Znth_same; auto. }
  rewrite ->!upd_Znth_same by auto.
  forward.
  forward_call (tint, tid, gv).
  { rewrite -> if_false by (intro; subst; contradiction); cancel. }
  set (locksp := gv _thread_locks).
  set (resultsp := gv _results).
  forward_for_simple_bound 3 (EX i : Z, EX ls : list bool,
    PROP (Zlength ls = i)
    LOCAL (temp _total (vint (Zlength (filter id ls))); temp _res res; temp _l lockt; temp _t (vint t);
           temp _arg tid; gvars gv)
    SEP (@data_at CompSpecs sh (tarray tentry size) entries (gv _m_entries); invariant N (hashtable_inv gh g lgk lgv);
         hashtable_A (repeat (0, ghosts.singleton O 0) (Z.to_nat size)) lgk lgv entries;
         EX h : _, !!(add_events empty_map (map (fun j => HAdd (j + 1) 1 (Znth j ls)) (upto (Z.to_nat i))) h) &&
           ghost_hist gsh h gh;
         data_at sh (tarray (tptr (Tstruct _lock_t noattr)) 3) (upd_Znth t (repeat Vundef 3) lockt) locksp;
         data_at sh (tarray (tptr tint) 3) (upd_Znth t (repeat Vundef 3) res) resultsp;
         data_at_ Tsh tint res;
         lock_inv tsh lockt (f_lock_pred N gv tsh sh gsh entries gh g lgk lgv t lockt res inv_names))).
  - Exists (@nil bool) (@nil (nat * hashtable_hist_el)); entailer!.
  - Intros h.
    forward_call (i + 1, 1, p, sh, entries, g, lgk, lgv, repeat (0, ghosts.singleton 0 0) (Z.to_nat size), ghost_hist gsh h gh,
      fun (_ : Z -> option (Z -> option Z)) (x : (bool * (Z -> option Z))) => EX h' : _,
        !!(add_events h [HAdd (i + 1) 1 (fst x)] h') && ghost_hist gsh h' gh,
      fun H => ghost_hist gsh h gh * EX hr : _, !!(apply_hist empty_map hr H) && ghost_ref hr gh,
      fun _ : Z => hashtable_inv gh g lgk lgv, [0]).
    { simpl; entailer!.
      split; [split|].
      + pose proof (Int.min_signed_neg); omega.
      + transitivity 4; [omega | computable].
      + split; [|pose proof size_pos; rewrite ->Zlength_repeat, Z2Nat.id by omega; auto].
        match goal with H : Forall (fun '(pk, pv) => isptr pk /\ isptr pv) entries |- _ =>
          eapply Forall_impl, H end; intros (?, ?); auto. }
    { split; simpl; rewrite ->sepcon_emp.
      + unfold hashtable_inv; split; apply derives_view_shift; Intros HT; Exists HT; cancel.
      + intros HT (b, lv).
        view_shift_intro hr; view_shift_intros.
        rewrite ->sepcon_comm.
        rewrite ->(add_andp (ghost_hist _ _ _ * _) (!!hist_incl h hr)), andp_comm by (apply hist_ref_incl; auto).
        view_shift_intros.
        etransitivity; [apply view_shift_sepcon1|].
        { apply hist_add' with (e := HAdd (i + 1) 1 b); auto. }
        apply derives_view_shift.
        unfold hashtable_inv; Exists (h ++ [(length hr, HAdd (i + 1) 1 b)]); entailer!.
        { apply add_events_1, hist_incl_lt; auto. }
        Exists (if b then map_upd HT (Zlength x + 1) lv else HT) (hr ++ [HAdd (Zlength x + 1) 1 b]); entailer!.
        rewrite ->apply_hist_app; do 2 eexists; eauto; simpl.
        destruct b.
        * split; [tauto|].
          do 2 eexists; eauto.
          unfold HT_upd; do 2 eexists; eauto.
          match goal with H : _ <-> true = true |- _=> destruct H as (_ & Hc) end.
          rewrite ->Hc; auto.
        * split; auto.
          match goal with H : _ <-> false = true |- _=> destruct H as (Hc & _) end.
          intro X; specialize (Hc X); discriminate. }
    Intro y; destruct y as ((s, lv), HT); simpl.
    Intros T h'.
    focus_SEP 1; apply hashtable_A_forget; auto.
    { rewrite ->Forall_forall_Znth with (d := (0, empty_map)); intros j ?.
      match goal with H : table_incl _ _ |- _ => specialize (H j); rewrite ->Znth_repeat' in H by (rewrite Z2Nat.id; omega); destruct H end.
      destruct (Znth j T (0, empty_map)); auto. }
    match goal with |- semax _ (PROP () (LOCALx (?a :: ?b :: temp _total _ :: ?Q) (SEPx ?R))) _ _ =>
      forward_if (PROP () (LOCALx (a :: b :: temp _total (vint (Zlength (filter id (x ++ [s])))) :: Q)
                 (SEPx R))) end.
    + Intros; forward.
      subst; rewrite ->filter_app, Zlength_app; entailer!.
    + forward.
      subst; rewrite ->filter_app, Zlength_app; entailer!.
    + intros.
      unfold exit_tycon, overridePost.
      destruct (eq_dec ek EK_normal); [subst | apply ENTAIL_refl].
      Intros; unfold POSTCONDITION, abbreviate, normal_ret_assert, loop1_ret_assert, overridePost.
      Exists (x ++ [s]); rewrite ->?Zlength_app, ?Zlength_cons, ?Zlength_nil; entailer!.
      Exists h'; entailer!.
      rewrite ->Z2Nat.inj_add, upto_app, map_app, Z2Nat.id by omega; change (upto (Z.to_nat 1)) with [0]; simpl.
      rewrite ->Z.add_0_r, app_Znth2, Zminus_diag, Znth_0_cons by omega.
      eapply add_events_trans; eauto.
      erewrite map_ext_in; eauto.
      intros j Hj; rewrite ->app_Znth1; auto.
      rewrite ->In_upto, Z2Nat.id in Hj; omega.
  - Intros ls h.
    forward.
    forward_call (lockt, tsh, f_lock_inv sh gsh entries gh g lgk lgv p t locksp lockt resultsp res,
                  f_lock_pred tsh sh gsh entries gh g lgk lgv p t locksp lockt resultsp res).
    { assert_PROP (Zlength entries = size) by (pose proof size_pos; entailer!).
      lock_props.
      { apply f_pred_precise; auto; omega. }
      { apply selflock_rec. }
      unfold f_lock_pred at 2.
      rewrite ->selflock_eq.
      unfold f_lock_inv at 1.
      rewrite ->lock_struct_array.
      Exists (Znth 0 ls false) (Znth 1 ls false) (Znth 2 ls false) h; entailer!.
      rewrite ->(list_Znth_eq false ls) at 1.
      replace (length ls) with (Z.to_nat 3) by (symmetry; rewrite <- Zlength_length by computable; auto).
      cancel.
      subst Frame; instantiate (1 := []); simpl; rewrite ->sepcon_emp; apply lock_inv_later. }
    forward.
Qed.

Lemma lock_struct : forall p, data_at_ Tsh (Tstruct _lock_t noattr) p |-- data_at_ Tsh tlock p.
Proof.
  intros.
  unfold data_at_, field_at_; unfold_field_at 1%nat.
  unfold field_at, at_offset; simpl.
  rewrite ->field_compatible_cons; simpl; entailer!.
Qed.

Lemma add_fails : forall k v b l H H' (HH : apply_hist H l H') (Hadd : In (HAdd k v b) l)
  (Hk : H k <> None), b = false.
Proof.
  induction l; simpl; intros; [contradiction|].
  destruct a; try (destruct Hadd as [X|]; [inv X|]).
  - destruct HH as (? & (? & ? & ?) & ?); subst.
    eapply IHl; eauto.
    unfold map_upd; if_tac; auto; discriminate.
  - destruct HH; eauto.
  - destruct b; auto.
    destruct HH, (H k); [discriminate | contradiction].
  - destruct (H k0), r; destruct HH as (? & HH); try discriminate; eauto.
    destruct HH as (? & (? & ? & ?) & ?); subst.
    eapply IHl; eauto.
    unfold map_upd; if_tac; auto; discriminate.
Qed.

Lemma only_one_add_succeeds : forall k v1 v2 l i1 i2 H0 H (HH : apply_hist H0 l H)
  (Hin1 : Znth i1 l (HGet 0 0) = HAdd k v1 true) (Hin2 : Znth i2 l (HGet 0 0) = HAdd k v2 true),
  i2 = i1 /\ v2 = v1.
Proof.
  induction l; simpl; intros.
  { rewrite ->Znth_nil in Hin1; discriminate. }
  assert (i2 = i1); [|subst; rewrite ->Hin2 in Hin1; inv Hin1; auto].
  exploit (Znth_inbounds i1 (a :: l) (HGet 0 0)); [rewrite Hin1; discriminate|].
  exploit (Znth_inbounds i2 (a :: l) (HGet 0 0)); [rewrite Hin2; discriminate|].
  rewrite ->!Zlength_cons; intros.
  destruct (eq_dec i1 0), (eq_dec i2 0); subst; auto.
  - rewrite ->Znth_0_cons in Hin1; subst.
    rewrite ->Znth_pos_cons in Hin2 by omega.
    destruct HH as (? & ? & (? & ? & ?) & HH), (H0 k); [discriminate | subst].
    eapply add_fails in HH; [|rewrite <- Hin2; apply Znth_In; omega|]; [discriminate|].
    unfold map_upd; rewrite ->eq_dec_refl; discriminate.
  - rewrite ->Znth_0_cons in Hin2; subst.
    rewrite ->Znth_pos_cons in Hin1 by omega.
    destruct HH as (? & ? & (? & ? & ?) & HH), (H0 k); [discriminate | subst].
    eapply add_fails in HH; [|rewrite <- Hin1; apply Znth_In; omega|]; [discriminate|].
    unfold map_upd; rewrite ->eq_dec_refl; discriminate.
  - rewrite ->Znth_pos_cons in Hin1, Hin2 by omega.
    assert (i2 - 1 = i1 - 1); [|omega].
    destruct a.
    + destruct HH as (? & ? & ?); eapply IHl; eauto.
    + destruct HH, (H0 k0); eapply IHl; eauto.
    + destruct (H0 k0), r, HH as (? & HH); try discriminate; try solve [eapply IHl; eauto].
      destruct HH as (? & ? & ?); eapply IHl; eauto.
Qed.

Lemma one_add_succeeds : forall k v b l H0 H (HH : apply_hist H0 l H) (Hk : H0 k = None)
  (Hin : In (HAdd k v b) l) (Hout : forall v, ~In (HSet k v) l), exists v', In (HAdd k v' true) l.
Proof.
  induction l; simpl; intros; [contradiction|].
  assert (forall v, ~In (HSet k v) l).
  { intros v0 ?; contradiction (Hout v0); auto. }
  destruct a; try (destruct Hin as [X|]; [discriminate|]).
  - destruct (eq_dec k0 k); [contradiction (Hout v0); subst; auto|].
    destruct HH as (? & (? & ? & ?) & ?); subst.
    exploit IHl; eauto.
    { unfold map_upd; if_tac; auto; subst; contradiction. }
    intros (? & ?); eauto.
  - destruct (H0 k0), HH; exploit IHl; eauto; intros (? & ?); eauto.
  - destruct (eq_dec k0 k).
    + subst; rewrite ->Hk in HH.
      destruct r; [eauto | destruct HH; contradiction].
    + destruct Hin as [X|]; [inv X; contradiction|].
      destruct (H0 k0), r, HH as (? & HH); try discriminate; try solve [exploit IHl; eauto; intros (? & ?); eauto].
      destruct HH as (? & (? & ? & ?) & ?); subst.
      exploit IHl; eauto; [|intros (? & ?); eauto].
      unfold map_upd; if_tac; auto; subst; contradiction.
Qed.

Lemma filter_find_count : forall {A} (f : A -> bool) d l li (Hunique : NoDup li)
  (Hli : forall i, In i li -> f (Znth i l d) = true) (Hrest : forall i, ~In i li -> f (Znth i l d) = false),
  Zlength (filter f l) = Zlength li.
Proof.
  induction l; simpl; intros.
  - exploit (list_pigeonhole li (Zlength li + 1)); [omega|].
    intros (i' & ? & ?).
    destruct li; auto.
    exploit (Hli z); simpl; auto.
    exploit Hrest; eauto.
    rewrite ->!Znth_nil; intros ->; discriminate.
  - assert (f d = false) as Hd.
    { exploit (list_pigeonhole (upto (Z.to_nat (Zlength (a :: l))) ++ li)
       (Zlength (upto (Z.to_nat (Zlength (a :: l))) ++ li) + 1)); [omega|].
      intros (j' & ? & Hout); exploit (Hrest j').
      { intro X; contradiction Hout; rewrite ->in_app; auto. }
      rewrite ->Znth_overflow; auto.
      { destruct (zlt j' (Zlength (a :: l))); auto.
        contradiction Hout; rewrite ->in_app; left.
        rewrite ->In_upto, Z2Nat.id; omega. } }
    destruct (in_dec Z.eq_dec 0 li).
    + exploit Hli; eauto.
      rewrite ->Znth_0_cons; intros ->.
      rewrite ->Zlength_cons.
      exploit in_split; eauto; intros (li1 & li2 & ?); subst.
      apply NoDup_remove in Hunique; destruct Hunique.
      rewrite ->Zlength_app, Zlength_cons.
      erewrite (IHl (map (fun i => i - 1) (li1 ++ li2))), Zlength_map, Zlength_app; auto; try omega.
      * apply FinFun.Injective_map_NoDup; auto.
        intros ??; omega.
      * intros ? Hj; rewrite ->in_map_iff in Hj; destruct Hj as (j & ? & Hj); subst.
        exploit (Hli j).
        { rewrite ->in_insert_iff; auto. }
        destruct (eq_dec j 0); [subst; contradiction|].
        destruct (zlt j 0).
        { rewrite ->Znth_underflow, Hd by auto; discriminate. }
        rewrite ->Znth_pos_cons by omega; auto.
      * intros j Hj.
        destruct (zlt j 0); [rewrite Znth_underflow; auto|].
        specialize (Hrest (j + 1)); specialize (Hli (j + 1));
          rewrite ->Znth_pos_cons, Z.add_simpl_r in Hrest, Hli by omega.
        destruct (in_dec Z.eq_dec (j + 1) (li1 ++ 0 :: li2)); auto.
        rewrite ->in_insert_iff in i0; destruct i0; [omega|].
        contradiction Hj; rewrite ->in_map_iff; do 2 eexists; eauto; omega.
    + exploit Hrest; eauto.
      rewrite ->Znth_0_cons; intros ->.
      erewrite (IHl (map (fun i => i - 1) li)), Zlength_map; try omega.
      * apply FinFun.Injective_map_NoDup; auto.
        intros ??; omega.
      * intros ? Hj; rewrite ->in_map_iff in Hj; destruct Hj as (j & ? & Hj); subst.
        specialize (Hli _ Hj).
        destruct (eq_dec j 0); [subst; contradiction|].
        destruct (zlt j 0).
        { rewrite ->Znth_underflow, Hd in Hli by auto; discriminate. }
        rewrite ->Znth_pos_cons in Hli by omega; auto.
      * intros j Hj.
        destruct (zlt j 0); [rewrite Znth_underflow; auto|].
        specialize (Hrest (j + 1)); specialize (Hli (j + 1));
          rewrite ->Znth_pos_cons, Z.add_simpl_r in Hrest, Hli by omega.
        destruct (in_dec Z.eq_dec (j + 1) li); auto.
        contradiction Hj; rewrite ->in_map_iff; do 2 eexists; eauto; omega.
Qed.

Lemma hists_eq : forall lr (Hlr : Forall (fun '(h, ls) => add_events []
  [HAdd 1 1 (Znth 0 ls false); HAdd 2 1 (Znth 1 ls false); HAdd 3 1 (Znth 2 ls false)] h) lr)
  (Hlens : Forall (fun '(_, ls) => Zlength ls = 3) lr),
  map snd lr = map (fun x => map (fun e => match snd e with | HAdd _ _ b => b | _ => false end) (fst x)) lr.
Proof.
  intros; apply list_Znth_eq' with (d := []); rewrite ->!Zlength_map; auto.
  intros.
  rewrite ->!Znth_map with (d' := ([], [])) by auto.
  apply Forall_Znth with (i := j)(d := ([], [])) in Hlr; auto.
  apply Forall_Znth with (i := j)(d := ([], [])) in Hlens; auto.
  destruct (Znth j lr ([], [])); simpl.
  apply add_events_add in Hlr; destruct Hlr as (l' & ? & Heq); subst.
  destruct l0; [discriminate | rewrite ->Zlength_cons in *].
  destruct l0; [discriminate | rewrite ->Zlength_cons in *].
  destruct l0; [discriminate | rewrite ->Zlength_cons in *].
  destruct l0; [|rewrite Zlength_cons in *; pose proof (Zlength_nonneg l0); omega].
  destruct l' as [|(?, ?)]; [discriminate | inv Heq].
  destruct l' as [|(?, ?)]; [discriminate | match goal with H : map _ _ = _ |- _ => inv H end].
  destruct l' as [|(?, ?)]; [discriminate | match goal with H : map _ _ = _ |- _ => inv H end].
  destruct l'; [auto | match goal with H : map _ _ = _ |- _ => inv H end].
Qed.

Lemma add_three : forall lr HT l (Hlr : Zlength lr = 3)
  (Hhists : Forall (fun '(h, ls) => add_events [] [HAdd 1 1 (Znth 0 ls false); HAdd 2 1 (Znth 1 ls false);
     HAdd 3 1 (Znth 2 ls false)] h) lr) (Hlens : Forall (fun '(_, ls) => Zlength ls = 3) lr)
  (Hl : hist_list (concat (map fst lr)) l) (HHT : apply_hist empty_map l HT),
  Zlength (filter id (concat (map snd lr))) = 3.
Proof.
  intros.
  assert (Permutation.Permutation (filter id (concat (map snd lr)))
    (filter id (map (fun e => match e with HAdd _ _ b => b | _ => false end) l))) as Hperm.
  { apply Permutation_filter.
    apply hist_list_perm in Hl.
    etransitivity; [|apply Permutation.Permutation_map; eauto].
    rewrite ->map_map, concat_map, map_map, hists_eq; auto. }
  destruct Hl as (HNoDup & Hl).
  rewrite ->(Permutation_Zlength _ _ Hperm).
  assert (forall k v, ~ In (HSet k v) l).
  { repeat intro.
    apply In_nth_error in H; destruct H as (? & H).
    rewrite <- Hl, in_concat in H; destruct H as (? & ? & Hin).
    rewrite ->in_map_iff in Hin; destruct Hin as ((h, ?) & ? & Hin); subst.
    assert (In (HSet k v) (map snd h)) as Hin' by (rewrite in_map_iff; do 2 eexists; eauto; auto).
    rewrite ->Forall_forall in Hhists; specialize (Hhists _ Hin); simpl in Hhists.
    erewrite add_events_snd in Hin' by eauto; simpl in Hin'.
    decompose [or] Hin'; try discriminate; contradiction. }
  assert (forall i, 0 <= i < 3 -> In (HAdd (i + 1) 1 (Znth i (snd (Znth 0 lr ([], []))) false)) l) as Hins.
  { intros.
    assert (exists t, In (t, HAdd (i + 1) 1 (Znth i (snd (Znth 0 lr ([], []))) false)) (concat (map fst lr)))
      as (t & Hin).
    { setoid_rewrite in_concat; setoid_rewrite in_map_iff.
      exploit (Znth_In 0 lr ([], [])); [omega | intro Hin].
      rewrite ->Forall_forall in Hhists; specialize (Hhists _ Hin).
      destruct (Znth 0 lr ([], [])) as (h, ?); simpl in *.
      exploit (Znth_In i (map snd h) (HGet 0 0)).
      { erewrite add_events_snd; eauto; simpl.
        rewrite ->!Zlength_cons, Zlength_nil; auto. }
      intro Hin'; rewrite ->in_map_iff in Hin'; destruct Hin' as ((t, ?) & ? & Hin'); simpl in *; subst.
      erewrite add_events_snd in Hin' by eauto; simpl in Hin'.
      do 3 eexists; eauto.
      destruct (eq_dec i 0); [subst; apply Hin'|].
      destruct (eq_dec i 1); [subst; apply Hin'|].
      destruct (eq_dec i 2); [subst; apply Hin' | omega]. }
    rewrite ->Hl in Hin; eapply nth_error_in; eauto. }
  exploit (one_add_succeeds 1 1 (Znth 0 (snd (Znth 0 lr ([], []))) false) l); eauto.
  { eapply (Hins 0); auto; omega. }
  exploit (one_add_succeeds 2 1 (Znth 1 (snd (Znth 0 lr ([], []))) false) l); eauto.
  { eapply (Hins 1); auto; omega. }
  exploit (one_add_succeeds 3 1 (Znth 2 (snd (Znth 0 lr ([], []))) false) l); eauto.
  { eapply (Hins 2); auto; omega. }
  intros (v3 & Hin3) (v2 & Hin2) (v1 & Hin1).
  apply In_Znth with (d := HGet 0 0) in Hin1; destruct Hin1 as (t1 & ? & Ht1).
  apply In_Znth with (d := HGet 0 0) in Hin2; destruct Hin2 as (t2 & ? & Ht2).
  apply In_Znth with (d := HGet 0 0) in Hin3; destruct Hin3 as (t3 & ? & Ht3).
  rewrite ->filter_find_count with (d := false)(li := [t1; t2; t3]); auto; simpl.
  - repeat constructor; auto; simpl.
    + intros [|[|]]; try contradiction; subst.
      * rewrite ->Ht1 in Ht2; inv Ht2.
      * rewrite ->Ht1 in Ht3; inv Ht3.
    + intros [|]; try contradiction; subst.
      rewrite ->Ht2 in Ht3; inv Ht3.
  - intros ? [|[|[|]]]; try contradiction; subst; erewrite Znth_map by auto.
    + rewrite ->Ht1; auto.
    + rewrite ->Ht2; auto.
    + rewrite ->Ht3; auto.
  - intros i Hi.
    destruct (zlt i 0); [rewrite Znth_underflow; auto|].
    destruct (zlt i (Zlength l)); [|rewrite Znth_overflow by (rewrite Zlength_map; omega); auto].
    erewrite Znth_map with (d' := HGet 0 0) by omega.
    destruct (Znth i l (HGet 0 0)) eqn: Hith; auto.
    destruct r; auto.
    contradiction Hi.
    assert (k = 1 \/ k = 2 \/ k = 3) as Hk.
    { rewrite <- (Z2Nat.id i), <- nth_Znth in Hith by omega.
      exploit nth_error_nth; [apply Nat2Z.inj_lt; rewrite ->Z2Nat.id, <- Zlength_correct; eauto; omega|].
      rewrite ->Hith; intro Hin.
      rewrite <- Hl, in_concat in Hin; destruct Hin as (? & ? & Hin).
      rewrite ->in_map_iff in Hin; destruct Hin as ((h, ?) & ? & Hin); subst.
      assert (In (HAdd k v true) (map snd h)) as Hin' by (rewrite in_map_iff; do 2 eexists; eauto; auto).
      rewrite ->Forall_forall in Hhists; specialize (Hhists _ Hin); simpl in Hhists.
      erewrite add_events_snd in Hin' by eauto; destruct Hin' as [X | [X | [X | X]]]; inv X; auto. }
    destruct Hk as [|[|]]; [left | right; left | right; right; left];
      match goal with |-?P => assert (P /\ Znth (k - 1) [v1; v2; v3] 0 = v); [|tauto] end;
      subst; eapply only_one_add_succeeds; eauto.
Qed.

Lemma hashtable_A_join : forall lgk lgv entries,
  hashtable_A (repeat (0, ghosts.singleton 0 0) (Z.to_nat size)) lgk lgv entries * hashtable_A (repeat (0, singleton 0 0) (Z.to_nat size)) lgk lgv entries =
  hashtable_A (repeat (0, ghosts.singleton 0 0) (Z.to_nat size)) lgk lgv entries.
Proof.
  intros; unfold hashtable_A; rewrite <- sepcon_map.
  erewrite map_ext_in; eauto; intros.
  unfold hashtable_entry_A.
  destruct (Znth a entries (Vundef, Vundef)).
  rewrite ->Znth_repeat' by (rewrite In_upto in *; auto).
  assert (forall v, value_of (ghosts.singleton 0 0) v -> v = 0) as Hz.
  { intros ? (? & Hz & ?); unfold ghosts.singleton in Hz; destruct (eq_dec _ _); inv Hz; auto. }
  rewrite ->!sepcon_andp_prop', sepcon_andp_prop, <- andp_assoc, andp_dup.
  rewrite ->(sepcon_comm (k_state _ _ _ _)) at 1.
  erewrite <- sepcon_assoc, (sepcon_assoc (v_state _ _ _ _)), protocol_A_join by apply join_refl.
  erewrite (sepcon_comm (v_state _ _ _ _)), sepcon_assoc, protocol_A_join by apply join_refl; auto.
Qed.

Lemma body_main : semax_body Vprog Gprog f_main main_spec.
Proof.
  name m_entries _m_entries.
  name locksp _thread_locks.
  name resp _results.
  name keys _keys.
  name values _values.
  start_function.
  replace 16384 with size by (setoid_rewrite (proj2_sig has_size); auto).
  forward.
  forward_call m_entries.
  { fast_cancel. }
  Intros x; destruct x as (((entries, g), lgk), lgv).
  apply ghost_alloc with (g0 := (Some (Tsh, [] : hist), Some ([] : hist))); auto with init.
  Intro gh.
  rewrite <- hist_ref_join_nil by (apply Share.nontrivial); Intros.
  gather_SEP 4 1; apply make_inv with (Q := hashtable_inv gh g lgk lgv).
  { unfold hashtable_inv, hashtable; Exists (@empty_map Z (Z -> option Z)) (@nil hashtable_hist_el); entailer!. }
  { unfold hashtable_inv, hashtable, hashtable_entry; prove_objective.
    destruct (Znth _ _ _); auto with objective. }
  destruct (split_shares 3 Ews) as (sh0 & shs & ? & ? & ? & Hshs); auto.
  destruct (split_shares 3 Tsh) as (sh0' & shs' & ? & ? & ? & Hshs'); auto.
  destruct (split_readable_share Tsh) as (sh1 & sh2 & ? & ? & ?); auto.
  rewrite <- seq_assoc.
  set (f_lock j l r := f_lock_pred sh2 (Znth j shs Ews) (Znth j shs' Tsh) entries gh g lgk lgv m_entries
                                         j locksp l resp r).
  forward_for_simple_bound 3 (EX i : Z, PROP ()
    LOCAL (temp _total (vint 0); lvar _values (tarray tint size) values;
           lvar _keys (tarray tint size) keys; gvar _results resp;
           gvar _thread_locks locksp; gvar _m_entries m_entries)
    SEP (@data_at CompSpecs Ews (tarray tentry size) entries m_entries;
         data_at_ Tsh (tarray tint size) values; data_at_ Tsh (tarray tint size) keys;
         invariant (hashtable_inv gh g lgk lgv); ghost_hist Tsh ([] : hist) gh;
         iter_sepcon (fun x => malloc_token Tsh 4 (fst x) * malloc_token Tsh 4 (snd x))
           entries; hashtable_A (repeat (0, ghosts.singleton 0 0) (Z.to_nat size)) lgk lgv entries;
         EX res : list val, !!(Zlength res = i) &&
           data_at Ews (tarray (tptr tint) 3) (res ++ repeat Vundef (Z.to_nat (3 - i))) resp *
           iter_sepcon (data_at_ Tsh tint) res *
           iter_sepcon (malloc_token Tsh (sizeof tint)) res *
         EX locks : list val, !!(Zlength locks = i) &&
           data_at Ews (tarray (tptr (Tstruct _lock_t noattr)) 3)
             (locks ++ repeat Vundef (Z.to_nat (3 - i))) locksp *
           iter_sepcon (malloc_token Tsh (sizeof (Tstruct _lock_t noattr))) locks *
           iter_sepcon (fun j => lock_inv Tsh (Znth j locks Vundef)
             (f_lock j (Znth j locks Vundef) (Znth j res Vundef))) (upto (Z.to_nat i)))).
  { Exists (@nil val) (@nil val); rewrite ->!data_at__eq; entailer!.
    erewrite map_ext; eauto; intros (?, ?); auto. }
  { (* first loop *)
    Intros res locks.
    forward_malloc (Tstruct _lock_t noattr) l.
    rewrite ->sepcon_map; Intros.
    forward.
    forward_malloc tint r.
    forward.
    focus_SEP 3.
    forward_call (l, Tsh, f_lock i l r).
    { rewrite ->!sepcon_assoc; apply sepcon_derives; [apply lock_struct | cancel_frame]. }
    Exists (res ++ [r]) (locks ++ [l]); rewrite ->!Zlength_app, !Zlength_cons, !Zlength_nil; entailer!.
    rewrite ->lock_inv_isptr, data_at__isptr; Intros.
    rewrite ->Z2Nat.inj_add, upto_app, !map_app, !sepcon_app by omega.
    simpl; change (upto 1) with [0]; simpl.
    rewrite ->Z2Nat.id, Z.add_0_r by omega.
    replace (Zlength res + 1) with (Zlength (res ++ [r]))
      by (rewrite Zlength_app, Zlength_cons, Zlength_nil; auto).
    rewrite <- upd_complete_gen by omega.
    replace (Zlength (res ++ [r])) with (Zlength (locks ++ [l]))
      by (rewrite !Zlength_app, !Zlength_cons, !Zlength_nil; auto; omega).
    rewrite <- upd_complete_gen by omega.
    rewrite ->!app_Znth2 by omega.
    replace (Zlength locks) with (Zlength res); rewrite ->Zminus_diag, !Znth_0_cons.
    destruct r; try contradiction.
    destruct l; try contradiction.
    rewrite ->sepcon_map; cancel.
    apply sepcon_list_derives; rewrite ->!Zlength_map, !Zlength_upto, <- Zlength_correct.
    { rewrite ->Z2Nat.id; auto; omega. }
    intros.
    erewrite !Znth_map, !Znth_upto by (rewrite ?Zlength_upto, <- ?Zlength_correct, ?Z2Nat.id; auto; omega).
    rewrite ->!app_Znth1 by omega; auto. }
  Intros res locks.
  rewrite ->!app_nil_r.
  assert_PROP (Zlength entries = size) by (pose proof size_pos; entailer!).
  rewrite <- seq_assoc.
  forward_for_simple_bound 3 (EX i : Z, EX sh : share,
    PROP (sepalg_list.list_join sh0 (sublist i 3 shs) sh)
    LOCAL (temp _total (vint 0); lvar _values (tarray tint size) values; lvar _keys (tarray tint size) keys;
           gvar _results resp; gvar _thread_locks locksp; gvar _m_entries m_entries)
    SEP (@data_at CompSpecs sh (tarray tentry size) entries m_entries;
         data_at_ Tsh (tarray tint size) values; data_at_ Tsh (tarray tint size) keys;
         invariant (hashtable_inv gh g lgk lgv);
         EX sh' : _, !!(sepalg_list.list_join sh0' (sublist i 3 shs') sh') && ghost_hist sh' ([] : hist) gh;
         iter_sepcon (fun x => malloc_token Tsh 4 (fst x) * malloc_token Tsh 4 (snd x))
           entries; hashtable_A (repeat (0, ghosts.singleton 0 0) (Z.to_nat size)) lgk lgv entries;
         data_at sh (tarray (tptr tint) 3) res resp;
         iter_sepcon (data_at_ Tsh tint) (sublist i 3 res);
         iter_sepcon (malloc_token Tsh (sizeof tint)) res;
         data_at sh (tarray (tptr (Tstruct _lock_t noattr)) 3) locks locksp;
         iter_sepcon (malloc_token Tsh (sizeof (Tstruct _lock_t noattr))) locks;
         iter_sepcon (fun j => lock_inv (if zlt j i then sh1 else Tsh) (Znth j locks Vundef)
           (f_lock j (Znth j locks Vundef) (Znth j res Vundef))) (upto 3))).
  { rewrite ->!sublist_same by auto; Exists Ews Tsh; entailer!. }
  { (* second loop *)
    forward_malloc tint t.
    Intros sh'.
    rewrite ->sepcon_map; Intros.
    forward.
    simpl in *; assert (3 <= Zlength shs) by omega.
    match goal with H : sepalg_list.list_join sh0 _ _ |- _ => rewrite ->sublist_next with (d := Ews) in H by auto;
      inversion H as [|????? Hj1 Hj2]; subst end.
    apply sepalg.join_comm in Hj1; destruct (sepalg_list.list_join_assoc1 Hj1 Hj2) as (sh3 & ? & Hj3).
    assert (3 <= Zlength shs') by omega.
    match goal with H : sepalg_list.list_join sh0' _ _ |- _ => rewrite ->sublist_next with (d := Tsh) in H by auto;
      inversion H as [|????? Hj1' Hj2']; subst end.
    apply sepalg.join_comm in Hj1'; destruct (sepalg_list.list_join_assoc1 Hj1' Hj2') as (sh3' & ? & Hj3').
    rewrite <- hashtable_A_join.
    rewrite ->invariant_duplicable.
    get_global_function'' _f; Intros.
    apply extract_exists_pre; intros f_.
    forward_spawn (share * share * share * list (val * val) * val * val * list val * list val * val * Z * val * val * val * val)%type
      (f_, t, (fun x : (share * share * share * list (val * val) * val * val * list val * list val * val * Z * val * val * val * val) =>
        let '(sh, gsh, tsh, entries, gh, g, lgk, lgv, p, t, locksp, lockt, resultsp, res) := x in
        [(_m_entries, p); (_thread_locks, locksp); (_results, resultsp)]),
        (Znth i shs Ews, Znth i shs' Tsh, sh2, entries, gh, g, lgk, lgv, m_entries, i, locksp, Znth i locks Vundef, resp,
               Znth i res Vundef),
    fun (x : (share * share * share * list (val * val) * val * val * list val * list val * val * Z * val * val * val * val)%type)
        (tid : val) =>
    let '(sh, gsh, tsh, entries, gh, g, lgk, lgv, p, t, locksp, lockt, resultsp, res) := x in
    fold_right sepcon emp
      [!!(0 <= t < 3 /\ isptr lockt /\ readable_share sh /\ readable_share tsh /\ gsh <> Share.bot /\
          Forall (fun '(pk, pv) => isptr pk /\ isptr pv) entries /\ Zlength lgk = size /\ Zlength lgv = size) && emp;
        data_at sh (tarray tentry size) entries p; invariant (hashtable_inv gh g lgk lgv);
        hashtable_A (repeat (0, ghosts.singleton 0 0) (Z.to_nat size)) lgk lgv entries; ghost_hist gsh (@nil (nat * hashtable_hist_el)) gh;
        data_at Tsh tint (vint t) tid; malloc_token Tsh (sizeof tint) tid;
        data_at sh (tarray (tptr tlock) 3) (upd_Znth t (repeat Vundef 3) lockt) locksp;
        data_at sh (tarray (tptr tint) 3) (upd_Znth t (repeat Vundef 3) res) resultsp;
        data_at_ Tsh tint res;
        lock_inv tsh lockt (f_lock_pred tsh sh gsh entries gh g lgk lgv p t locksp lockt resultsp res)]).
    { unfold spawn_pre; go_lower.
      erewrite gvar_eval_var, !(force_val_sem_cast_neutral_gvar' _ f_), !force_val_sem_cast_neutral_isptr' by
        (rewrite ?force_val_sem_cast_neutral_isptr'; eauto).
      assert (0 <= i < Zlength shs) by omega.
      assert (Znth i shs' Tsh <> Share.bot).
      { intro X; contradiction unreadable_bot; rewrite <- X.
        apply Forall_Znth; auto; omega. }
      rewrite ->(extract_nth_sepcon (map _ (upto 3)) i) by (rewrite Zlength_map; auto).
      erewrite Znth_map, Znth_upto by (auto; simpl; omega).
      destruct (zlt i i); [omega|].
      rewrite ->lock_inv_isptr; Intros.
      Exists _arg; entailer!.
      { repeat split; try apply gvar_denote_global; auto.
        apply Forall_Znth; auto. }
      rewrite ->!sepcon_assoc; apply sepcon_derives.
      { apply derives_refl'.
        f_equal; f_equal; extensionality.
        destruct x0 as (?, x0); repeat destruct x0 as (x0, ?); simpl.
        extensionality; apply mpred_ext; entailer!. }
      rewrite <- !(data_at_share_join _ _ _ _ _ _ Hj3).
      rewrite ->(add_andp (ghost_hist _ _ _) (!!disjoint ([] : hist) [])) by entailer!.
      rewrite ->andp_comm, <- (ghost_hist_join _ _ _ _ _ _ _ Hj3'); auto.
      rewrite <- (lock_inv_share_join sh1 sh2) by auto.
      fast_cancel; cancel.
      rewrite ->(sepcon_comm _ (data_at (Znth i shs Ews) _ _ locksp)), !sepcon_assoc; apply sepcon_derives.
      { rewrite ->lock_struct_array; apply stronger_array_ext.
        - unfold unfold_reptype; simpl; rewrite ->upd_Znth_Zlength; auto.
        - intros j ???; unfold unfold_reptype; simpl.
          destruct (eq_dec j i).
          + subst; rewrite ->upd_Znth_same; auto.
          + rewrite ->upd_Znth_diff by auto.
            rewrite ->Znth_repeat with (x1 := Vundef)(n0 := 3%nat); apply stronger_default_val. }
      rewrite <- !sepcon_assoc, (sepcon_comm _ (data_at (Znth i shs Ews) _ _ resp)),
        !sepcon_assoc; apply sepcon_derives.
      { apply stronger_array_ext.
        - unfold unfold_reptype; simpl; rewrite ->upd_Znth_Zlength; auto.
        - intros j ???; unfold unfold_reptype; simpl.
          destruct (eq_dec j i).
          + subst; rewrite ->upd_Znth_same; auto.
          + rewrite ->upd_Znth_diff' by auto.
            rewrite ->Znth_repeat with (x1 := Vundef)(n0 := 3%nat); apply stronger_default_val. }
      erewrite sublist_next by (auto; omega); simpl; fast_cancel.
      { intro; subst; contradiction unreadable_bot.
        eapply join_readable1, readable_share_list_join; eauto. } }
    go_lower.
    Exists sh3 sh3'; rewrite ->sepcon_map; entailer!.
    rewrite ->replace_nth_sepcon; apply sepcon_list_derives; rewrite ->upd_Znth_Zlength; rewrite ->!Zlength_map;
      auto.
    intros j ?; destruct (eq_dec j i).
    - subst; rewrite ->upd_Znth_same by auto.
      erewrite Znth_map, Znth_upto by (auto; simpl; omega).
      if_tac; [auto | omega].
    - rewrite ->upd_Znth_diff' by auto.
      erewrite !Znth_map, !Znth_upto by (auto; rewrite ->Zlength_upto in *; omega).
      if_tac; if_tac; auto; omega. }
  Intros sh sh'.
  rewrite ->sublist_nil.
  repeat match goal with H : sepalg_list.list_join _ (sublist 3 3 _) _ |- _ =>
    rewrite ->sublist_nil in H; inv H end.
  forward_for_simple_bound 3 (EX i : Z, EX x : (share * (list (hist * list bool))),
    PROP (readable_share (fst x); sepalg_list.list_join (fst x) (sublist i 3 shs) Ews; Zlength (snd x) = i;
          Forall (fun p => let '(h, ls) := p in add_events []
            [HAdd 1 1 (Znth 0 ls false); HAdd 2 1 (Znth 1 ls false); HAdd 3 1 (Znth 2 ls false)] h) (snd x);
          Forall (fun '(h, ls) => Zlength ls = 3) (snd x))
    LOCAL (let ls := map snd (snd x) in temp _total (vint (Zlength (filter id (concat ls))));
           lvar _values (tarray tint size) values; lvar _keys (tarray tint size) keys; gvar _results resp;
           gvar _thread_locks locksp; gvar _m_entries m_entries)
    SEP (@data_at CompSpecs (fst x) (tarray tentry size) entries m_entries;
         invariant (hashtable_inv gh g lgk lgv);
         EX sh' : share, !!(readable_share sh' /\ sepalg_list.list_join sh' (sublist i 3 shs') Tsh) &&
           let h := map fst (snd x) in ghost_hist sh' (concat h) gh;
         iter_sepcon (fun x => malloc_token Tsh 4 (fst x) * malloc_token Tsh 4 (snd x))
           entries; hashtable_A (repeat (0, ghosts.singleton 0 0) (Z.to_nat size)) lgk lgv entries;
         data_at_ Tsh (tarray tint size) values; data_at_ Tsh (tarray tint size) keys;
         data_at (fst x) (tarray (tptr tint) 3) res resp;
         iter_sepcon (malloc_token Tsh (sizeof tint)) (sublist i 3 res);
         data_at (fst x) (tarray (tptr (Tstruct _lock_t noattr)) 3) locks locksp;
         iter_sepcon (malloc_token Tsh (sizeof (Tstruct _lock_t noattr))) (sublist i 3 locks);
         iter_sepcon (fun j => lock_inv sh1 (Znth j locks Vundef)
           (f_lock j (Znth j locks Vundef) (Znth j res Vundef))) (sublist i 3 (upto 3)))).
  { rewrite ->!(sublist_same 0 3) by auto.
    Exists (sh, @nil (hist * list bool)) sh'; entailer!. }
  { (* third loop *)
    destruct x as (sh3, lr); Intros sh3'; simpl in *.
    erewrite sublist_next with (l := upto 3), Znth_upto by (auto; rewrite ->?Zlength_upto; simpl; omega); simpl.
    rewrite ->lock_inv_isptr, sepcon_map; Intros.
    forward.
    forward_call (Znth i locks Vundef, sh1, f_lock i (Znth i locks Vundef) (Znth i res Vundef)).
    forward_call (Znth i locks Vundef, Tsh, sh2,
      |>f_lock_inv (Znth i shs Ews) (Znth i shs' Tsh) entries gh g lgk lgv m_entries i locksp (Znth i locks Vundef) resp (Znth i res Vundef),
      |>f_lock i (Znth i locks Vundef) (Znth i res Vundef)).
    { rewrite ->?sepcon_assoc; rewrite <- sepcon_emp at 1; rewrite ->sepcon_comm; apply sepcon_derives;
        [repeat apply andp_right; auto; eapply derives_trans;
         try (apply precise_weak_precise || apply positive_weak_positive || apply rec_inv_weak_rec_inv); auto |].
      { apply later_positive; subst f_lock; simpl; auto. }
      { apply later_rec_lock, selflock_rec. }
      unfold f_lock at 2; unfold f_lock_pred.
      rewrite ->selflock_eq.
      rewrite <- !sepcon_assoc, (sepcon_comm _ (lock_inv _ _ _)), !sepcon_assoc, <- sepcon_assoc;
        apply sepcon_derives; [|cancel_frame].
      rewrite <- (lock_inv_share_join sh1 sh2 Tsh) by auto; unfold f_lock, f_lock_pred; cancel.
      apply lock_inv_later. }
    erewrite sublist_next with (l := locks) by (auto; omega); simpl.
    forward_call (Znth i locks Vundef, sizeof (Tstruct _lock_t noattr)).
    { entailer!. }
    { entailer!. }
    { fast_cancel.
      apply sepcon_derives; [|cancel_frame].
      rewrite ->data_at__memory_block; Intros; auto. }
    unfold f_lock_inv at 1; Intros b1 b2 b3 hi.
    assert (0 <= i < Zlength shs) by omega.
    assert (readable_share (Znth i shs Ews)) by (apply Forall_Znth; auto).
    forward.
    { assert (0 <= i < 3) as Hi by auto; clear - Hi; entailer!.
      rewrite ->upd_Znth_same; auto. }
    rewrite ->upd_Znth_same by auto.
    forward.
    erewrite sublist_next with (l := res) by (auto; omega); simpl.
    forward_call (Znth i res Vundef, sizeof tint).
    { entailer!. }
    { entailer!. }
    { fast_cancel.
      rewrite <- !sepcon_assoc, (sepcon_comm _ (data_at _ _ _ (Znth i res Vundef))), !sepcon_assoc;
        apply sepcon_derives; [|cancel_frame].
      apply data_at_memory_block. }
    assert (3 <= Zlength shs) by omega.
    match goal with H : sepalg_list.list_join sh3 _ _ |- _ => rewrite ->sublist_next with (d := Ews) in H by auto;
      inversion H as [|??? w1 ? Hj1]; subst end.
    match goal with H : sepalg_list.list_join sh3' _ _ |- _ => rewrite ->sublist_next with (d := Tsh) in H by (auto; omega);
      inversion H as [|??? w1' ? Hj1']; subst end.
    gather_SEP 16 2.
    replace_SEP 0 (data_at w1 (tarray (tptr (Tstruct _lock_t noattr)) 3) locks locksp).
    { go_lower.
      rewrite <- lock_struct_array.
      eapply derives_trans; [apply data_at_array_value_cohere; auto|].
      erewrite data_at_share_join; eauto. }
    gather_SEP 14 3.
    replace_SEP 0 (data_at w1 (tarray (tptr tint) 3) res resp).
    { go_lower.
      eapply derives_trans; [apply data_at_array_value_cohere; auto|].
      erewrite data_at_share_join; eauto. }
    gather_SEP 5 6; rewrite <- invariant_duplicable.
    gather_SEP 9 10; rewrite ->hashtable_A_join.
    gather_SEP 7 4; erewrite ghost_hist_join; eauto.
    gather_SEP 6 5; erewrite data_at_share_join by eauto.
    forward.
    go_lower; Exists (w1, lr ++ [(hi, [b1; b2; b3])]) w1'; rewrite ->sepcon_map; entailer!.
    rewrite ->map_app, concat_app, filter_app, !Zlength_app, Zlength_cons, Zlength_nil; simpl;
      repeat (split; auto).
    - eapply join_readable1; eauto.
    - rewrite ->Forall_app; repeat constructor; auto.
    - rewrite ->Forall_app; repeat constructor; auto.
    - eapply join_readable1; eauto.
    - rewrite ->map_app, concat_app; simpl.
      rewrite ->app_nil_r; auto.
    - intro; subst; contradiction unreadable_bot.
    - intro X; contradiction unreadable_bot; rewrite <- X.
      apply Forall_Znth; auto; omega. }
  Intros x sh''; destruct x as (?, lr); simpl in *.
  repeat match goal with H : sepalg_list.list_join _ (sublist 3 3 _) _ |- _ =>
    rewrite ->sublist_nil in H; inv H end.
  gather_SEP 2 1; apply invariant_view_shift with (Q := !!(exists l HT, hist_list (concat (map fst lr)) l /\
    apply_hist empty_map l HT) && ghost_hist Tsh (concat (map fst lr)) gh).
  { eapply view_shift_assert; [|intro X; rewrite ->prop_true_andp by (apply X); reflexivity].
    unfold hashtable_inv; Intros HT hr.
    rewrite <- sepcon_assoc, (sepcon_comm _ (ghost_ref _ _)), <- sepcon_assoc,
      (sepcon_comm _ (ghost_hist _ _ _)).
    rewrite ->hist_ref_join by (apply Share.nontrivial).
    Intros h'; apply prop_right.
    exists hr, HT; split; auto.
    match goal with H : hist_sub _ _ _ |- _ => unfold hist_sub in H; rewrite ->eq_dec_refl in H; subst; auto end. }
  Intros.
  match goal with H : exists l HT, _ |- _ => destruct H as (? & ? & ? & ?) end.
Ltac entailer_for_return ::= idtac.
  unfold size, hf1; simpl.
  rewrite ->(proj2_sig has_size).
  forward.
  { entailer!. }
  rewrite <- (proj2_sig has_size).
  entailer!.
Qed.
