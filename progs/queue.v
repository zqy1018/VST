Require Import Clightdefs.

Local Open Scope Z_scope.

Definition _i : ident := 65%positive.
Definition ___builtin_bswap32 : ident := 40%positive.
Definition ___builtin_annot : ident := 16%positive.
Definition ___i64_sar : ident := 38%positive.
Definition ___builtin_fmin : ident := 46%positive.
Definition _n : ident := 62%positive.
Definition _freeN : ident := 54%positive.
Definition ___builtin_va_end : ident := 22%positive.
Definition _tail : ident := 12%positive.
Definition _fifo_get : ident := 63%positive.
Definition _next : ident := 10%positive.
Definition ___builtin_fsqrt : ident := 44%positive.
Definition ___builtin_negl : ident := 3%positive.
Definition ___builtin_write32_reversed : ident := 2%positive.
Definition ___builtin_write16_reversed : ident := 1%positive.
Definition ___i64_utof : ident := 31%positive.
Definition ___builtin_fnmadd : ident := 49%positive.
Definition _j : ident := 66%positive.
Definition _t : ident := 59%positive.
Definition ___builtin_addl : ident := 4%positive.
Definition _h : ident := 58%positive.
Definition ___i64_stod : ident := 28%positive.
Definition _a : ident := 7%positive.
Definition ___builtin_va_copy : ident := 21%positive.
Definition ___builtin_membar : ident := 18%positive.
Definition ___builtin_fmax : ident := 45%positive.
Definition _fifo : ident := 13%positive.
Definition ___i64_dtou : ident := 27%positive.
Definition ___i64_udiv : ident := 33%positive.
Definition _fifo_new : ident := 56%positive.
Definition ___compcert_va_float64 : ident := 25%positive.
Definition ___builtin_memcpy_aligned : ident := 15%positive.
Definition _fifo_put : ident := 60%positive.
Definition ___builtin_va_arg : ident := 20%positive.
Definition ___i64_sdiv : ident := 32%positive.
Definition ___compcert_va_int64 : ident := 24%positive.
Definition _main : ident := 67%positive.
Definition ___builtin_annot_intval : ident := 17%positive.
Definition _b : ident := 8%positive.
Definition ___builtin_subl : ident := 5%positive.
Definition ___builtin_fnmsub : ident := 50%positive.
Definition ___builtin_ctz : ident := 43%positive.
Definition _mallocN : ident := 53%positive.
Definition ___builtin_fmadd : ident := 47%positive.
Definition _p : ident := 57%positive.
Definition ___i64_shl : ident := 36%positive.
Definition ___builtin_fabs : ident := 14%positive.
Definition ___builtin_mull : ident := 6%positive.
Definition ___i64_dtos : ident := 26%positive.
Definition ___builtin_va_start : ident := 19%positive.
Definition ___builtin_bswap : ident := 39%positive.
Definition _fifo_empty : ident := 61%positive.
Definition _head : ident := 11%positive.
Definition ___i64_shr : ident := 37%positive.
Definition ___builtin_clz : ident := 42%positive.
Definition _elem : ident := 9%positive.
Definition _make_elem : ident := 64%positive.
Definition ___builtin_read32_reversed : ident := 52%positive.
Definition ___builtin_bswap16 : ident := 41%positive.
Definition ___i64_smod : ident := 34%positive.
Definition ___i64_utod : ident := 29%positive.
Definition _Q : ident := 55%positive.
Definition ___i64_umod : ident := 35%positive.
Definition ___i64_stof : ident := 30%positive.
Definition ___compcert_va_int32 : ident := 23%positive.
Definition ___builtin_read16_reversed : ident := 51%positive.
Definition ___builtin_fmsub : ident := 48%positive.

Definition f_fifo_new := {|
  fn_return := (tptr (Tstruct _fifo noattr));
  fn_callconv := cc_default;
  fn_params := nil;
  fn_vars := nil;
  fn_temps := ((_Q, (tptr (Tstruct _fifo noattr))) ::
               (68%positive, (tptr tvoid)) :: nil);
  fn_body :=
(Ssequence
  (Ssequence
    (Scall (Some 68%positive)
      (Evar _mallocN (Tfunction (Tcons tint Tnil) (tptr tvoid) cc_default))
      ((Esizeof (Tstruct _fifo noattr) tuint) :: nil))
    (Sset _Q
      (Ecast (Etempvar 68%positive (tptr tvoid))
        (tptr (Tstruct _fifo noattr)))))
  (Ssequence
    (Sassign
      (Efield
        (Ederef (Etempvar _Q (tptr (Tstruct _fifo noattr)))
          (Tstruct _fifo noattr)) _head (tptr (Tstruct _elem noattr)))
      (Ecast (Econst_int (Int.repr 0) tint) (tptr tvoid)))
    (Ssequence
      (Sassign
        (Efield
          (Ederef (Etempvar _Q (tptr (Tstruct _fifo noattr)))
            (Tstruct _fifo noattr)) _tail (tptr (Tstruct _elem noattr)))
        (Ecast (Econst_int (Int.repr 0) tint) (tptr tvoid)))
      (Sreturn (Some (Etempvar _Q (tptr (Tstruct _fifo noattr))))))))
|}.

Definition f_fifo_put := {|
  fn_return := tvoid;
  fn_callconv := cc_default;
  fn_params := ((_Q, (tptr (Tstruct _fifo noattr))) ::
                (_p, (tptr (Tstruct _elem noattr))) :: nil);
  fn_vars := nil;
  fn_temps := ((_h, (tptr (Tstruct _elem noattr))) ::
               (_t, (tptr (Tstruct _elem noattr))) :: nil);
  fn_body :=
(Ssequence
  (Sassign
    (Efield
      (Ederef (Etempvar _p (tptr (Tstruct _elem noattr)))
        (Tstruct _elem noattr)) _next (tptr (Tstruct _elem noattr)))
    (Ecast (Econst_int (Int.repr 0) tint) (tptr tvoid)))
  (Ssequence
    (Sset _h
      (Efield
        (Ederef (Etempvar _Q (tptr (Tstruct _fifo noattr)))
          (Tstruct _fifo noattr)) _head (tptr (Tstruct _elem noattr))))
    (Sifthenelse (Ebinop Oeq (Etempvar _h (tptr (Tstruct _elem noattr)))
                   (Ecast (Econst_int (Int.repr 0) tint) (tptr tvoid)) tint)
      (Ssequence
        (Sassign
          (Efield
            (Ederef (Etempvar _Q (tptr (Tstruct _fifo noattr)))
              (Tstruct _fifo noattr)) _head (tptr (Tstruct _elem noattr)))
          (Etempvar _p (tptr (Tstruct _elem noattr))))
        (Sassign
          (Efield
            (Ederef (Etempvar _Q (tptr (Tstruct _fifo noattr)))
              (Tstruct _fifo noattr)) _tail (tptr (Tstruct _elem noattr)))
          (Etempvar _p (tptr (Tstruct _elem noattr)))))
      (Ssequence
        (Sset _t
          (Efield
            (Ederef (Etempvar _Q (tptr (Tstruct _fifo noattr)))
              (Tstruct _fifo noattr)) _tail (tptr (Tstruct _elem noattr))))
        (Ssequence
          (Sassign
            (Efield
              (Ederef (Etempvar _t (tptr (Tstruct _elem noattr)))
                (Tstruct _elem noattr)) _next (tptr (Tstruct _elem noattr)))
            (Etempvar _p (tptr (Tstruct _elem noattr))))
          (Sassign
            (Efield
              (Ederef (Etempvar _Q (tptr (Tstruct _fifo noattr)))
                (Tstruct _fifo noattr)) _tail (tptr (Tstruct _elem noattr)))
            (Etempvar _p (tptr (Tstruct _elem noattr)))))))))
|}.

Definition f_fifo_empty := {|
  fn_return := tint;
  fn_callconv := cc_default;
  fn_params := ((_Q, (tptr (Tstruct _fifo noattr))) :: nil);
  fn_vars := nil;
  fn_temps := ((_h, (tptr (Tstruct _elem noattr))) :: nil);
  fn_body :=
(Ssequence
  (Sset _h
    (Efield
      (Ederef (Etempvar _Q (tptr (Tstruct _fifo noattr)))
        (Tstruct _fifo noattr)) _head (tptr (Tstruct _elem noattr))))
  (Sreturn (Some (Ebinop Oeq (Etempvar _h (tptr (Tstruct _elem noattr)))
                   (Ecast (Econst_int (Int.repr 0) tint) (tptr tvoid)) tint))))
|}.

Definition f_fifo_get := {|
  fn_return := (tptr (Tstruct _elem noattr));
  fn_callconv := cc_default;
  fn_params := ((_Q, (tptr (Tstruct _fifo noattr))) :: nil);
  fn_vars := nil;
  fn_temps := ((_h, (tptr (Tstruct _elem noattr))) ::
               (_n, (tptr (Tstruct _elem noattr))) :: nil);
  fn_body :=
(Ssequence
  (Sset _h
    (Efield
      (Ederef (Etempvar _Q (tptr (Tstruct _fifo noattr)))
        (Tstruct _fifo noattr)) _head (tptr (Tstruct _elem noattr))))
  (Ssequence
    (Sset _n
      (Efield
        (Ederef (Etempvar _h (tptr (Tstruct _elem noattr)))
          (Tstruct _elem noattr)) _next (tptr (Tstruct _elem noattr))))
    (Ssequence
      (Sassign
        (Efield
          (Ederef (Etempvar _Q (tptr (Tstruct _fifo noattr)))
            (Tstruct _fifo noattr)) _head (tptr (Tstruct _elem noattr)))
        (Etempvar _n (tptr (Tstruct _elem noattr))))
      (Sreturn (Some (Etempvar _h (tptr (Tstruct _elem noattr))))))))
|}.

Definition f_make_elem := {|
  fn_return := (tptr (Tstruct _elem noattr));
  fn_callconv := cc_default;
  fn_params := ((_a, tint) :: (_b, tint) :: nil);
  fn_vars := nil;
  fn_temps := ((_p, (tptr (Tstruct _elem noattr))) ::
               (69%positive, (tptr tvoid)) :: nil);
  fn_body :=
(Ssequence
  (Ssequence
    (Scall (Some 69%positive)
      (Evar _mallocN (Tfunction (Tcons tint Tnil) (tptr tvoid) cc_default))
      ((Esizeof (Tstruct _elem noattr) tuint) :: nil))
    (Sset _p (Etempvar 69%positive (tptr tvoid))))
  (Ssequence
    (Sassign
      (Efield
        (Ederef (Etempvar _p (tptr (Tstruct _elem noattr)))
          (Tstruct _elem noattr)) _a tint) (Etempvar _a tint))
    (Ssequence
      (Sassign
        (Efield
          (Ederef (Etempvar _p (tptr (Tstruct _elem noattr)))
            (Tstruct _elem noattr)) _b tint) (Etempvar _b tint))
      (Sreturn (Some (Etempvar _p (tptr (Tstruct _elem noattr))))))))
|}.

Definition f_main := {|
  fn_return := tint;
  fn_callconv := cc_default;
  fn_params := nil;
  fn_vars := nil;
  fn_temps := ((_i, tint) :: (_j, tint) ::
               (_Q, (tptr (Tstruct _fifo noattr))) ::
               (_p, (tptr (Tstruct _elem noattr))) ::
               (73%positive, (tptr (Tstruct _elem noattr))) ::
               (72%positive, (tptr (Tstruct _elem noattr))) ::
               (71%positive, (tptr (Tstruct _elem noattr))) ::
               (70%positive, (tptr (Tstruct _fifo noattr))) :: nil);
  fn_body :=
(Ssequence
  (Ssequence
    (Scall (Some 70%positive)
      (Evar _fifo_new (Tfunction Tnil (tptr (Tstruct _fifo noattr))
                        cc_default)) nil)
    (Sset _Q (Etempvar 70%positive (tptr (Tstruct _fifo noattr)))))
  (Ssequence
    (Ssequence
      (Scall (Some 71%positive)
        (Evar _make_elem (Tfunction (Tcons tint (Tcons tint Tnil))
                           (tptr (Tstruct _elem noattr)) cc_default))
        ((Econst_int (Int.repr 1) tint) :: (Econst_int (Int.repr 10) tint) ::
         nil))
      (Sset _p (Etempvar 71%positive (tptr (Tstruct _elem noattr)))))
    (Ssequence
      (Scall None
        (Evar _fifo_put (Tfunction
                          (Tcons (tptr (Tstruct _fifo noattr))
                            (Tcons (tptr (Tstruct _elem noattr)) Tnil)) tvoid
                          cc_default))
        ((Etempvar _Q (tptr (Tstruct _fifo noattr))) ::
         (Etempvar _p (tptr (Tstruct _elem noattr))) :: nil))
      (Ssequence
        (Ssequence
          (Scall (Some 72%positive)
            (Evar _make_elem (Tfunction (Tcons tint (Tcons tint Tnil))
                               (tptr (Tstruct _elem noattr)) cc_default))
            ((Econst_int (Int.repr 2) tint) ::
             (Econst_int (Int.repr 20) tint) :: nil))
          (Sset _p (Etempvar 72%positive (tptr (Tstruct _elem noattr)))))
        (Ssequence
          (Scall None
            (Evar _fifo_put (Tfunction
                              (Tcons (tptr (Tstruct _fifo noattr))
                                (Tcons (tptr (Tstruct _elem noattr)) Tnil))
                              tvoid cc_default))
            ((Etempvar _Q (tptr (Tstruct _fifo noattr))) ::
             (Etempvar _p (tptr (Tstruct _elem noattr))) :: nil))
          (Ssequence
            (Ssequence
              (Scall (Some 73%positive)
                (Evar _fifo_get (Tfunction
                                  (Tcons (tptr (Tstruct _fifo noattr)) Tnil)
                                  (tptr (Tstruct _elem noattr)) cc_default))
                ((Etempvar _Q (tptr (Tstruct _fifo noattr))) :: nil))
              (Sset _p (Etempvar 73%positive (tptr (Tstruct _elem noattr)))))
            (Ssequence
              (Sset _i
                (Efield
                  (Ederef (Etempvar _p (tptr (Tstruct _elem noattr)))
                    (Tstruct _elem noattr)) _a tint))
              (Ssequence
                (Sset _j
                  (Efield
                    (Ederef (Etempvar _p (tptr (Tstruct _elem noattr)))
                      (Tstruct _elem noattr)) _b tint))
                (Ssequence
                  (Scall None
                    (Evar _freeN (Tfunction
                                   (Tcons (tptr tvoid) (Tcons tint Tnil))
                                   tvoid cc_default))
                    ((Etempvar _p (tptr (Tstruct _elem noattr))) ::
                     (Esizeof (Tstruct _elem noattr) tuint) :: nil))
                  (Sreturn (Some (Ebinop Oadd (Etempvar _i tint)
                                   (Etempvar _j tint) tint))))))))))))
|}.

Definition composites : list composite_definition :=
(Composite _elem Struct
   ((_a, tint) :: (_b, tint) :: (_next, (tptr (Tstruct _elem noattr))) ::
    nil)
   noattr ::
 Composite _fifo Struct
   ((_head, (tptr (Tstruct _elem noattr))) ::
    (_tail, (tptr (Tstruct _elem noattr))) :: nil)
   noattr :: nil).

Definition prog : Clight.program := {|
prog_defs :=
((___builtin_fabs,
   Gfun(External (EF_builtin ___builtin_fabs
                   (mksignature (AST.Tfloat :: nil) (Some AST.Tfloat)
                     cc_default)) (Tcons tdouble Tnil) tdouble cc_default)) ::
 (___builtin_memcpy_aligned,
   Gfun(External (EF_builtin ___builtin_memcpy_aligned
                   (mksignature
                     (AST.Tint :: AST.Tint :: AST.Tint :: AST.Tint :: nil)
                     None cc_default))
     (Tcons (tptr tvoid)
       (Tcons (tptr tvoid) (Tcons tuint (Tcons tuint Tnil)))) tvoid
     cc_default)) ::
 (___builtin_annot,
   Gfun(External (EF_builtin ___builtin_annot
                   (mksignature (AST.Tint :: nil) None
                     {|cc_vararg:=true; cc_structret:=false|}))
     (Tcons (tptr tschar) Tnil) tvoid
     {|cc_vararg:=true; cc_structret:=false|})) ::
 (___builtin_annot_intval,
   Gfun(External (EF_builtin ___builtin_annot_intval
                   (mksignature (AST.Tint :: AST.Tint :: nil) (Some AST.Tint)
                     cc_default)) (Tcons (tptr tschar) (Tcons tint Tnil))
     tint cc_default)) ::
 (___builtin_membar,
   Gfun(External (EF_builtin ___builtin_membar
                   (mksignature nil None cc_default)) Tnil tvoid cc_default)) ::
 (___builtin_va_start,
   Gfun(External (EF_builtin ___builtin_va_start
                   (mksignature (AST.Tint :: nil) None cc_default))
     (Tcons (tptr tvoid) Tnil) tvoid cc_default)) ::
 (___builtin_va_arg,
   Gfun(External (EF_builtin ___builtin_va_arg
                   (mksignature (AST.Tint :: AST.Tint :: nil) None
                     cc_default)) (Tcons (tptr tvoid) (Tcons tuint Tnil))
     tvoid cc_default)) ::
 (___builtin_va_copy,
   Gfun(External (EF_builtin ___builtin_va_copy
                   (mksignature (AST.Tint :: AST.Tint :: nil) None
                     cc_default))
     (Tcons (tptr tvoid) (Tcons (tptr tvoid) Tnil)) tvoid cc_default)) ::
 (___builtin_va_end,
   Gfun(External (EF_builtin ___builtin_va_end
                   (mksignature (AST.Tint :: nil) None cc_default))
     (Tcons (tptr tvoid) Tnil) tvoid cc_default)) ::
 (___compcert_va_int32,
   Gfun(External (EF_external ___compcert_va_int32
                   (mksignature (AST.Tint :: nil) (Some AST.Tint) cc_default))
     (Tcons (tptr tvoid) Tnil) tuint cc_default)) ::
 (___compcert_va_int64,
   Gfun(External (EF_external ___compcert_va_int64
                   (mksignature (AST.Tint :: nil) (Some AST.Tlong)
                     cc_default)) (Tcons (tptr tvoid) Tnil) tulong
     cc_default)) ::
 (___compcert_va_float64,
   Gfun(External (EF_external ___compcert_va_float64
                   (mksignature (AST.Tint :: nil) (Some AST.Tfloat)
                     cc_default)) (Tcons (tptr tvoid) Tnil) tdouble
     cc_default)) ::
 (___i64_dtos,
   Gfun(External (EF_external ___i64_dtos
                   (mksignature (AST.Tfloat :: nil) (Some AST.Tlong)
                     cc_default)) (Tcons tdouble Tnil) tlong cc_default)) ::
 (___i64_dtou,
   Gfun(External (EF_external ___i64_dtou
                   (mksignature (AST.Tfloat :: nil) (Some AST.Tlong)
                     cc_default)) (Tcons tdouble Tnil) tulong cc_default)) ::
 (___i64_stod,
   Gfun(External (EF_external ___i64_stod
                   (mksignature (AST.Tlong :: nil) (Some AST.Tfloat)
                     cc_default)) (Tcons tlong Tnil) tdouble cc_default)) ::
 (___i64_utod,
   Gfun(External (EF_external ___i64_utod
                   (mksignature (AST.Tlong :: nil) (Some AST.Tfloat)
                     cc_default)) (Tcons tulong Tnil) tdouble cc_default)) ::
 (___i64_stof,
   Gfun(External (EF_external ___i64_stof
                   (mksignature (AST.Tlong :: nil) (Some AST.Tsingle)
                     cc_default)) (Tcons tlong Tnil) tfloat cc_default)) ::
 (___i64_utof,
   Gfun(External (EF_external ___i64_utof
                   (mksignature (AST.Tlong :: nil) (Some AST.Tsingle)
                     cc_default)) (Tcons tulong Tnil) tfloat cc_default)) ::
 (___i64_sdiv,
   Gfun(External (EF_external ___i64_sdiv
                   (mksignature (AST.Tlong :: AST.Tlong :: nil)
                     (Some AST.Tlong) cc_default))
     (Tcons tlong (Tcons tlong Tnil)) tlong cc_default)) ::
 (___i64_udiv,
   Gfun(External (EF_external ___i64_udiv
                   (mksignature (AST.Tlong :: AST.Tlong :: nil)
                     (Some AST.Tlong) cc_default))
     (Tcons tulong (Tcons tulong Tnil)) tulong cc_default)) ::
 (___i64_smod,
   Gfun(External (EF_external ___i64_smod
                   (mksignature (AST.Tlong :: AST.Tlong :: nil)
                     (Some AST.Tlong) cc_default))
     (Tcons tlong (Tcons tlong Tnil)) tlong cc_default)) ::
 (___i64_umod,
   Gfun(External (EF_external ___i64_umod
                   (mksignature (AST.Tlong :: AST.Tlong :: nil)
                     (Some AST.Tlong) cc_default))
     (Tcons tulong (Tcons tulong Tnil)) tulong cc_default)) ::
 (___i64_shl,
   Gfun(External (EF_external ___i64_shl
                   (mksignature (AST.Tlong :: AST.Tint :: nil)
                     (Some AST.Tlong) cc_default))
     (Tcons tlong (Tcons tint Tnil)) tlong cc_default)) ::
 (___i64_shr,
   Gfun(External (EF_external ___i64_shr
                   (mksignature (AST.Tlong :: AST.Tint :: nil)
                     (Some AST.Tlong) cc_default))
     (Tcons tulong (Tcons tint Tnil)) tulong cc_default)) ::
 (___i64_sar,
   Gfun(External (EF_external ___i64_sar
                   (mksignature (AST.Tlong :: AST.Tint :: nil)
                     (Some AST.Tlong) cc_default))
     (Tcons tlong (Tcons tint Tnil)) tlong cc_default)) ::
 (___builtin_bswap,
   Gfun(External (EF_builtin ___builtin_bswap
                   (mksignature (AST.Tint :: nil) (Some AST.Tint) cc_default))
     (Tcons tuint Tnil) tuint cc_default)) ::
 (___builtin_bswap32,
   Gfun(External (EF_builtin ___builtin_bswap32
                   (mksignature (AST.Tint :: nil) (Some AST.Tint) cc_default))
     (Tcons tuint Tnil) tuint cc_default)) ::
 (___builtin_bswap16,
   Gfun(External (EF_builtin ___builtin_bswap16
                   (mksignature (AST.Tint :: nil) (Some AST.Tint) cc_default))
     (Tcons tushort Tnil) tushort cc_default)) ::
 (___builtin_clz,
   Gfun(External (EF_builtin ___builtin_clz
                   (mksignature (AST.Tint :: nil) (Some AST.Tint) cc_default))
     (Tcons tuint Tnil) tuint cc_default)) ::
 (___builtin_ctz,
   Gfun(External (EF_builtin ___builtin_ctz
                   (mksignature (AST.Tint :: nil) (Some AST.Tint) cc_default))
     (Tcons tuint Tnil) tuint cc_default)) ::
 (___builtin_fsqrt,
   Gfun(External (EF_builtin ___builtin_fsqrt
                   (mksignature (AST.Tfloat :: nil) (Some AST.Tfloat)
                     cc_default)) (Tcons tdouble Tnil) tdouble cc_default)) ::
 (___builtin_fmax,
   Gfun(External (EF_builtin ___builtin_fmax
                   (mksignature (AST.Tfloat :: AST.Tfloat :: nil)
                     (Some AST.Tfloat) cc_default))
     (Tcons tdouble (Tcons tdouble Tnil)) tdouble cc_default)) ::
 (___builtin_fmin,
   Gfun(External (EF_builtin ___builtin_fmin
                   (mksignature (AST.Tfloat :: AST.Tfloat :: nil)
                     (Some AST.Tfloat) cc_default))
     (Tcons tdouble (Tcons tdouble Tnil)) tdouble cc_default)) ::
 (___builtin_fmadd,
   Gfun(External (EF_builtin ___builtin_fmadd
                   (mksignature
                     (AST.Tfloat :: AST.Tfloat :: AST.Tfloat :: nil)
                     (Some AST.Tfloat) cc_default))
     (Tcons tdouble (Tcons tdouble (Tcons tdouble Tnil))) tdouble
     cc_default)) ::
 (___builtin_fmsub,
   Gfun(External (EF_builtin ___builtin_fmsub
                   (mksignature
                     (AST.Tfloat :: AST.Tfloat :: AST.Tfloat :: nil)
                     (Some AST.Tfloat) cc_default))
     (Tcons tdouble (Tcons tdouble (Tcons tdouble Tnil))) tdouble
     cc_default)) ::
 (___builtin_fnmadd,
   Gfun(External (EF_builtin ___builtin_fnmadd
                   (mksignature
                     (AST.Tfloat :: AST.Tfloat :: AST.Tfloat :: nil)
                     (Some AST.Tfloat) cc_default))
     (Tcons tdouble (Tcons tdouble (Tcons tdouble Tnil))) tdouble
     cc_default)) ::
 (___builtin_fnmsub,
   Gfun(External (EF_builtin ___builtin_fnmsub
                   (mksignature
                     (AST.Tfloat :: AST.Tfloat :: AST.Tfloat :: nil)
                     (Some AST.Tfloat) cc_default))
     (Tcons tdouble (Tcons tdouble (Tcons tdouble Tnil))) tdouble
     cc_default)) ::
 (___builtin_read16_reversed,
   Gfun(External (EF_builtin ___builtin_read16_reversed
                   (mksignature (AST.Tint :: nil) (Some AST.Tint) cc_default))
     (Tcons (tptr tushort) Tnil) tushort cc_default)) ::
 (___builtin_read32_reversed,
   Gfun(External (EF_builtin ___builtin_read32_reversed
                   (mksignature (AST.Tint :: nil) (Some AST.Tint) cc_default))
     (Tcons (tptr tuint) Tnil) tuint cc_default)) ::
 (___builtin_write16_reversed,
   Gfun(External (EF_builtin ___builtin_write16_reversed
                   (mksignature (AST.Tint :: AST.Tint :: nil) None
                     cc_default)) (Tcons (tptr tushort) (Tcons tushort Tnil))
     tvoid cc_default)) ::
 (___builtin_write32_reversed,
   Gfun(External (EF_builtin ___builtin_write32_reversed
                   (mksignature (AST.Tint :: AST.Tint :: nil) None
                     cc_default)) (Tcons (tptr tuint) (Tcons tuint Tnil))
     tvoid cc_default)) ::
 (_mallocN,
   Gfun(External (EF_external _mallocN
                   (mksignature (AST.Tint :: nil) (Some AST.Tint) cc_default))
     (Tcons tint Tnil) (tptr tvoid) cc_default)) ::
 (_freeN,
   Gfun(External (EF_external _freeN
                   (mksignature (AST.Tint :: AST.Tint :: nil) None
                     cc_default)) (Tcons (tptr tvoid) (Tcons tint Tnil))
     tvoid cc_default)) :: (_fifo_new, Gfun(Internal f_fifo_new)) ::
 (_fifo_put, Gfun(Internal f_fifo_put)) ::
 (_fifo_empty, Gfun(Internal f_fifo_empty)) ::
 (_fifo_get, Gfun(Internal f_fifo_get)) ::
 (_make_elem, Gfun(Internal f_make_elem)) ::
 (_main, Gfun(Internal f_main)) :: nil);
prog_public :=
(_main :: _make_elem :: _fifo_get :: _fifo_empty :: _fifo_put :: _fifo_new ::
 _freeN :: _mallocN :: ___builtin_write32_reversed ::
 ___builtin_write16_reversed :: ___builtin_read32_reversed ::
 ___builtin_read16_reversed :: ___builtin_fnmsub :: ___builtin_fnmadd ::
 ___builtin_fmsub :: ___builtin_fmadd :: ___builtin_fmin ::
 ___builtin_fmax :: ___builtin_fsqrt :: ___builtin_ctz :: ___builtin_clz ::
 ___builtin_bswap16 :: ___builtin_bswap32 :: ___builtin_bswap ::
 ___i64_sar :: ___i64_shr :: ___i64_shl :: ___i64_umod :: ___i64_smod ::
 ___i64_udiv :: ___i64_sdiv :: ___i64_utof :: ___i64_stof :: ___i64_utod ::
 ___i64_stod :: ___i64_dtou :: ___i64_dtos :: ___compcert_va_float64 ::
 ___compcert_va_int64 :: ___compcert_va_int32 :: ___builtin_va_end ::
 ___builtin_va_copy :: ___builtin_va_arg :: ___builtin_va_start ::
 ___builtin_membar :: ___builtin_annot_intval :: ___builtin_annot ::
 ___builtin_memcpy_aligned :: ___builtin_fabs :: nil);
prog_main := _main;
prog_types := composites;
prog_comp_env := make_composite_env composites;
prog_comp_env_eq := refl_equal _
|}.

