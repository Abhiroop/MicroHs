-- Copyright 2023 Lennart Augustsson
-- See LICENSE file for full license.
module Text.String(module Text.String) where
import Primitives
import Data.Bool
import Data.Char
import Data.Either
import Data.Function
import Data.Int
import Data.List
import Data.Maybe
import Data.Ord
import Data.Tuple

showChar :: Char -> String
showChar c = "'" ++ encodeChar c ++ "'"

encodeChar :: Char -> String
encodeChar c =
  let
    spec = [('\n', "\\n"), ('\r', "\\r"), ('\t', "\\t"), ('\b', "\\b"),
            ('\\', "\\\\"), ('\'', "\\'"), ('"', "\"")]
  in
    case lookupBy eqChar c spec of
      Nothing -> if isPrint c then [c] else "'\\" ++ showInt (ord c) ++ "'"
      Just s  -> s

showString :: String -> String
showString s = "\"" ++ concatMap encodeChar s ++ "\""

-- XXX wrong for minInt
showInt :: Int -> String
showInt n =
  if n < 0 then
    '-' : showUnsignedInt (negate n)
  else
    showUnsignedInt n

showUnsignedInt :: Int -> String
showUnsignedInt n =
  let
    c = chr (ord '0' + rem n 10)
  in  if n < 10 then
        [c]
      else
        showUnsignedInt (quot n 10) ++ [c]

readInt :: String -> Int
readInt cs =
  let
    rd = foldl (\ a c -> a * 10 + ord c - ord '0') 0
  in if eqChar (head cs) '-' then 0 - rd (tail cs) else rd cs

showBool :: Bool -> String
showBool arg =
  case arg of
    False -> "False"
    True  -> "True"

showUnit :: () -> String
showUnit arg =
  case arg of
    () -> "()"

showPair :: forall a b . (a -> String) -> (b -> String) -> (a, b) -> String
showPair sa sb ab =
  case ab of
    (a, b) -> "(" ++ sa a ++ "," ++ sb b ++ ")"

showList :: forall a . (a -> String) -> [a] -> String
showList sa as = "[" ++ intercalate "," (map sa as) ++ "]"

showMaybe :: forall a . (a -> String) -> Maybe a -> String
showMaybe _ Nothing = "Nothing"
showMaybe fa (Just a) = "(Just " ++ fa a ++ ")"

showEither :: forall a b . (a -> String) -> (b -> String) -> Either a b -> String
showEither fa _ (Left  a) = "(Left "  ++ fa a ++ ")"
showEither _ fb (Right b) = "(Right " ++ fb b ++ ")"

showOrdering :: Ordering -> String
showOrdering LT = "LT"
showOrdering EQ = "EQ"
showOrdering GT = "GT"

lines :: String -> [String]
lines "" = []
lines s =
  case span (not . eqChar '\n') s of
    (l, s') -> case s' of { [] -> [l]; _:s'' -> l : lines s'' }

unlines :: [String] -> String
unlines = concatMap (++ "\n")


words :: String -> [String]
words s =
  case dropWhile isSpace s of
    "" -> []
    s' -> w : words s''
      where (w, s'') = span (not . isSpace) s'

unwords :: [String] -> String
unwords ss = intercalate " " ss

-- Using a primitive for string equality makes a huge speed difference.
eqString :: String -> String -> Bool
eqString = primEqString
{-
eqString axs ays =
  case axs of
    [] ->
      case ays of
        [] -> True
        _  -> False
    x:xs ->
      case ays of
        [] -> False
        y:ys -> eqChar x y && eqString xs ys
-}
leString :: String -> String -> Bool
leString s t = not (eqOrdering GT (compareString s t))
{-
leString axs ays =
  case axs of
    [] -> True
    x:xs ->
      case ays of
        [] -> False
        y:ys -> ltChar x y || eqChar x y && leString xs ys
-}

padLeft :: Int -> String -> String
padLeft n s = replicate (n - length s) ' ' ++ s

forceString :: String -> ()
forceString [] = ()
forceString (c:cs) = c `primSeq` forceString cs

{-
compareString :: [Char] -> [Char] -> Ordering
compareString s t =
  let
    r1 = compareString1 s t
    r2 = compareString2 s t
  in r2
    if eqOrdering r1 r2 then r1 else
    primError $ "compareString " ++ showString s ++ showString t ++ showOrdering r1 ++ showOrdering r2

compareString2 :: [Char] -> [Char] -> Ordering
compareString2 s t =
  if leString s t then
    if eqString s t then
      EQ
    else
      LT
  else
    GT
-}

compareString :: String -> String -> Ordering
compareString = primCompare
--compareString s t = if r < 0 then LT else if r > 0 then GT else EQ
--  where r = primCompare s t

