module ListTest(module ListTest) where
import Prelude
import Data.List
import System.IO
import String

main = do
  putStrLn $ showInt $ sum [1,2,3]
  putStrLn $ showInt $ product [1,2,3,4]
  putStrLn $ showBool $ and [True]
  putStrLn $ showBool $ and [True, False]
