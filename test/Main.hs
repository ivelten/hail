module Main (main) where

import qualified Spec as Spec
import Test.Hspec

main :: IO ()
main = hspec $ do
  Spec.spec
