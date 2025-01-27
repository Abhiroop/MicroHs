module Example(main) where
import Prelude

fac :: Int -> Int
fac 0 = 1
fac n = n * fac(n - 1)

main :: IO ()
main = do
  let
    rs = map fac [1,2,3,10]
  putStrLn "Some factorials"
  putStrLn $ showList showInt rs
