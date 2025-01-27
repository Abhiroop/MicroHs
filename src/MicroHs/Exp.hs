{-# OPTIONS_GHC -Wno-unused-imports #-}
-- Copyright 2023 Lennart Augustsson
-- See LICENSE file for full license.
module MicroHs.Exp(
  compileOpt,
  substExp,
  Exp(..), showExp, eqExp, toStringP,
  PrimOp,
  encodeString,
  app2, cCons, cNil, cFlip,
  allVarsExp, freeVars,
  ) where
import Prelude
import Data.Char
import Data.List
import MicroHs.Ident
import MicroHs.Expr(Lit(..), showLit, eqLit)
--Ximport Control.DeepSeq
--Ximport Compat
--Yimport Primitives(NFData(..))
--import Debug.Trace

type PrimOp = String

data Exp
  = Var Ident
  | App Exp Exp
  | Lam Ident Exp
  | Lit Lit
  --Xderiving (Show, Eq)

--Winstance NFData Exp where rnf (Var i) = rnf i; rnf (App f a) = rnf f `seq` rnf a; rnf (Lam i e) = rnf i `seq` rnf e; rnf (Lit l) = rnf l

eqExp :: Exp -> Exp -> Bool
eqExp (Var i1) (Var i2) = eqIdent i1 i2
eqExp (App f1 a1) (App f2 a2) = eqExp f1 f2 && eqExp a1 a2
eqExp (Lam i1 e1) (Lam i2 e2) = eqIdent i1 i2 && eqExp e1 e2
eqExp (Lit l1) (Lit l2) = eqLit l1 l2
eqExp _ _ = False

data MaybeApp = NotApp | IsApp Exp Exp

getApp :: Exp -> MaybeApp
getApp ae =
  case ae of
    App f a -> IsApp f a
    _       -> NotApp

getVar :: Exp -> Maybe Ident
getVar ae =
  case ae of
    Var v -> Just v
    _     -> Nothing

isPrim :: String -> Exp -> Bool
isPrim s ae =
  case ae of
    Lit (LPrim ss) -> eqString s ss
    _       -> False

isK :: Exp -> Bool
isK = isPrim "K"

isI :: Exp -> Bool
isI = isPrim "I"

isB :: Exp -> Bool
isB = isPrim "B"

isC :: Exp -> Bool
isC = isPrim "C"

isY :: Exp -> Bool
isY = isPrim "Y"

isP :: Exp -> Bool
isP = isPrim "P"

app2 :: Exp -> Exp -> Exp -> Exp
app2 f a1 a2 = App (App f a1) a2

app3 :: Exp -> Exp -> Exp -> Exp -> Exp
app3 f a1 a2 a3 = App (app2 f a1 a2) a3

cCons :: Exp
cCons = Lit (LPrim "O")

cNil :: Exp
cNil = Lit (LPrim "K")

cFlip :: Exp
cFlip = Lit (LPrim "C")

cId :: Exp
cId = Lit (LPrim "I")

cConst :: Exp
cConst = Lit (LPrim "K")

cSpread :: Exp
cSpread = Lit (LPrim "S")

cP :: Exp
cP = Lit (LPrim "P")

{-
eqExp :: Exp -> Exp -> Bool
eqExp ae1 ae2 =
  case ae1 of
    Var i1 ->
      case ae2 of
        Var i2 -> eqIdent i1 i2
        _ -> False
    App e11 e12 ->
      case ae2 of
        App e21 e22 -> eqExp e11 e21 && eqExp e12 e22
        _ -> False
    Lam i1 e1 ->
      case ae2 of
        Lam i2 e2 -> eqIdent i1 i2 && eqExp e1 e2
        _ -> False
    Int i1 ->
      case ae2 of
        Int i2 -> i1 == i2
        _ -> False
    Prim p1 ->
      case ae2 of
        Prim p2 -> eqString p1 p2
        _ -> False
-}

-- Avoid quadratic concatenation by using difference lists,
-- turning concatenation into function composition.
toStringP :: Exp -> (String -> String)
toStringP ae =
  case ae of
    Var x   -> (showIdent x ++)
    Lit (LStr s) ->
      -- Encode very short string directly as combinators.
      if length s > 1 then
        (quoteString s ++)
      else
        toStringP (encodeString s)
    Lit l   -> (showLit l ++)
    Lam x e -> (("(\\" ++ showIdent x ++ " ") ++) . toStringP e . (")" ++)
    App f a -> ("(" ++) . toStringP f . (" " ++) . toStringP a . (")" ++)

quoteString :: String -> String
quoteString s =
  let
    char c =
      if eqChar c '"' || eqChar c '\\' || ltChar c ' ' || ltChar '~' c then
        '\\' : showInt (ord c) ++ ['&']
      else
        [c]
  in '"' : concatMap char s ++ ['"']

encodeString :: String -> Exp
encodeString [] = cNil
encodeString (c:cs) = app2 cCons (Lit (LInt (ord c))) (encodeString cs)

compileOpt :: Exp -> Exp
compileOpt = improveT . compileExp

compileExp :: Exp -> Exp
compileExp ae =
  case ae of
    App f a -> App (compileExp f) (compileExp a)
    Lam x a -> abstract x a
    _       -> ae

abstract :: Ident -> Exp -> Exp
abstract x ae =
  case ae of
    Var y  -> if eqIdent x y then cId else cK (Var y)
    App f a -> cS (abstract x f) (abstract x a)
    Lam y e -> abstract x $ abstract y e
    Lit _ -> cK ae

cK :: Exp -> Exp
cK e  = App cConst e

cS :: Exp -> Exp -> Exp
cS a1 a2 =
 if isK a1 then cId else
  let
    r = cS2 a1 a2
  in
    case getApp a1 of
      NotApp -> r
      IsApp k1 e1 ->
        if isK k1 then
          case getApp a2 of
            IsApp k2 e2 ->
              if isK k2 then
                cK (App e1 e2)
              else
                cB e1 a2
            NotApp ->
              if isI a2 then
                e1
              else
                cB e1 a2
        else
          r
cS2 :: Exp -> Exp -> Exp
cS2 a1 a2 =
  case getApp a2 of
    NotApp -> cS3 a1 a2
    IsApp k2 e2 ->
      if isK k2 then
        cC a1 e2
      else
        cS3 a1 a2

cS3 :: Exp -> Exp -> Exp
cS3 a1 a2 =
  let
    r = app2 cSpread a1 a2
  in
    case getApp a1 of
      NotApp -> r
      IsApp be1 e2 ->
        case getApp be1 of
          NotApp -> r
          IsApp b1 e1 ->
            if isB b1 then
              cSS e1 e2 a2
            else
              r

{-
--cS e1 e2 | trace ("S (" ++ toString e1 ++ ") (" ++ toString e2 ++ ")") False = undefined
cS CK              _           = CI                -- S K e           = I
cS (App CK e1)     (App CK e2) = cK (App e1 e2)    -- S (K e1) (K e2) = K (e1 e2)
cS (App CK e1)     CI          = e1                -- S (K e1) I      = e1
cS (App CK e1)     e2          = cB e1 e2          -- S (K e1) e2     = B e1 e2
cS e1              (App CK e2) = cC e1 e2          -- S e1     (K e2) = C e1 e2
cS (App (App CB e1) e2) e3     = cSS e1 e2 e3      -- S (B e1 e2) e3  = S' e1 e2 e3
cS e1 e2                       = App2 CS e1 e2
-}

cC :: Exp -> Exp -> Exp
cC a1 e3 =
  let
    r = cC2 a1 e3
  in
    case getApp a1 of
      NotApp -> r
      IsApp x1 e2 ->
        case getApp x1 of
          NotApp -> r
          IsApp bc e1 ->
            if isB bc then
              cCC e1 e2 e3
            else if isC bc && isI e1 then
              app2 cP e2 e3
            else
              r

cC2 :: Exp -> Exp -> Exp
cC2 a1 a2 =
  let
    r = app2 cFlip a1 a2
  in
    case getVar a1 of
      Nothing -> r
      Just op ->
        case lookupBy eqIdent op flipOps of
          Just oq -> App (Var oq) a2
          Nothing -> r
{-
cC (App (App CB e1) e2) e3          = cCC e1 e2 e3      -- C (B e1 e2) e3  = C' e1 e2 e3
cC (Var op)             e2 | Just op' <- lookup op flipOps = App (Var op') e2 -- C op e = flip-op e
cC (App (App CC CI) e2) e3          = app2 CP e2 e3
cC e1                   e2          = app2 CC e1 e2
-}

cB :: Exp -> Exp -> Exp
cB a1 a2 =
  let
    r = cB2 a1 a2
  in
    case getApp a1 of
      NotApp -> r
      IsApp cb ck ->
        if isB cb && isK ck && isP a2 then
          Lit (LPrim "O")
        else
          r

cB2 :: Exp -> Exp -> Exp
cB2 a1 a2 =
  let
    r = cB3 a1 a2
  in
    case getApp a2 of
      IsApp x1 x2 ->
        case getApp x1 of
          IsApp cb ck ->
            if isY a1 && isB cb && isK ck then
              x2
            else
              r
          NotApp ->
            if isC a1 && isC x1 && isI x2 then
              cP
            else
              r
      NotApp -> r

cB3 :: Exp -> Exp -> Exp
cB3 a1 a2 =
  if isI a1 then
    a2
  else
    app2 (Lit (LPrim "B")) a1 a2

{-
cB (App CB CK) CP             = CO -- Cons
cB CY          (App (App CB CK) e) = e  -- B Y (B K e) = e
cB CC          (App CC CI)    = CP -- Pair
cB CI          e              = e  -- B I e = e
cB e1          e2             = app2 CB e1 e2
-}

cSS :: Exp -> Exp -> Exp -> Exp
cSS e1 e2 e3 = app3 (Lit (LPrim "S'")) e1 e2 e3

cCC :: Exp -> Exp -> Exp -> Exp
cCC e1 e2 e3 = app3 (Lit (LPrim "C'")) e1 e2 e3

-- This is a hack, it assumes things about the Prelude
flipOps :: [(Ident, Ident)]
flipOps =
  [(mkIdent "Data.Int.+",  mkIdent "Data.Int.+")
  ,(mkIdent "Data.Int.-",  mkIdent "Data.Int.subtract")
  ,(mkIdent "Data.Int.*",  mkIdent "Data.Int.*")
  ,(mkIdent "Data.Int.==", mkIdent "Data.Int.==")
  ,(mkIdent "Data.Int./=", mkIdent "Data.Int./=")
  ,(mkIdent "Data.Int.<",  mkIdent "Data.Int.>")
  ,(mkIdent "Data.Int.<=", mkIdent "Data.Int.>=")
  ,(mkIdent "Data.Int.>",  mkIdent "Data.Int.<")
  ,(mkIdent "Data.Int.>=", mkIdent "Data.Int.<=")
  ]

improveT :: Exp -> Exp
improveT ae =
  case getApp ae of
    NotApp -> ae
    IsApp f a ->
      let
        ff = improveT f
        aa = improveT a
      in
        if isK ff && isI aa then
          Lit (LPrim "A")
{- Using I x --> x does not improve things.
        else if isI ff then
          aa
-}
        else if isB ff && isK aa then
          Lit (LPrim "BK")
        else if isC ff && isI aa then
          Lit (LPrim "T")
        else if isB ff && isB aa then
          Lit (LPrim "B'")
        else
          let
            def =
              case getApp aa of
                IsApp ck e ->
                  if isY ff && isK ck then
                    e
                  else
                    App ff aa
                NotApp -> App ff aa
          in
            def
{-
            case getApp ff of
              IsApp xf xa ->
                if isK xf then
                  xa
                else
                  def
              NotApp -> def
-}
            
{-
-- K I      -->  A
-- C I      -->  T
-- B B      -->  B'
-- Y (K e)  -->  e
-- K x y    -->  x
improveT (App f a) =
  case (improveT f, improveT a) of
    (CK,                     CI) -> CA
--    (CI,                      e) -> e
    (CY,               App CK e) -> e
--    (App CK e1,              e2) -> e1
    (e1,                     e2) -> App e1 e2
improveT e = e
-}

showExp :: Exp -> String
showExp ae =
  case ae of
    Var i -> showIdent i
    App f a -> "(" ++ showExp f ++ " " ++ showExp a ++ ")"
    Lam i e -> "(\\" ++ showIdent i ++ ". " ++ showExp e ++ ")"
    Lit l -> showLit l

substExp :: Ident -> Exp -> Exp -> Exp
substExp si se ae =
  case ae of
    Var i -> if eqIdent i si then se else ae
    App f a -> App (substExp si se f) (substExp si se a)
    Lam i e -> if eqIdent si i then
                 ae
               else if elemBy eqIdent i (freeVars se) then
                 let
                   fe = allVarsExp e
                   ase = allVarsExp se
                   j = head [ v | n <- enumFrom 0, let { v = mkIdent ("a" ++ showInt n) }, not (elemBy eqIdent v ase), not (elemBy eqIdent v fe) ]
                 in
                   --trace ("substExp " ++ unwords [si, i, j]) $
                   Lam j (substExp si se (substExp i (Var j) e))
               else
                   Lam i (substExp si se e)
    Lit _ -> ae

freeVars :: Exp -> [Ident]
freeVars ae =
  case ae of
    Var i -> [i]
    App f a -> freeVars f ++ freeVars a
    Lam i e -> deleteAllBy eqIdent i (freeVars e)
    Lit _ -> []

allVarsExp :: Exp -> [Ident]
allVarsExp ae =
  case ae of
    Var i -> [i]
    App f a -> allVarsExp f ++ allVarsExp a
    Lam i e -> i : allVarsExp e
    Lit _ -> []

--------
-- Possible additions
--
--  R = C C
--  R x y z = (C C x y) z = C y x z = y z x
--
--  Q = C I
--  Q x y z = (C I x y) z = I y x z = y x z
--
-- Added:
--  BK = B K
--  BK x y z = B K x y z = K (x y) z = x y
--
--  BKK = BK K
--  BKK x y z = BK K x y z = (K x) z = x
--
--  C'B = C' B
--  C'B x y z w = C' B x y z w = B (x z) y w = x z (y w)

--  B (B e) x y z = B e (x y) z = e (x y z)
--
--  B' :: (a -> b -> c) -> a -> (d -> b) -> d -> c
--  B' k f g x = k f (g x)
--
-- Common:
--  817: C' B
--  616: B BK
--  531: C' C
--  352: BK K
--  305: C' S
--
--  BBK = B BK
--  BBK x y z w = B BK x y z w = BK (x y) z w = x y z
--
--  C'C = C' C
--  C'C x y z w = C' C x y z w = C (x z) y w = x z w y


