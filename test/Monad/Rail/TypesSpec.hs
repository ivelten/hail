{-# LANGUAGE OverloadedStrings #-}

module Monad.Rail.TypesSpec (spec) where

import Control.Monad.IO.Class (liftIO)
import qualified Control.Exception as Ex
import Data.IORef (newIORef, readIORef, modifyIORef)
import Data.List (isInfixOf)
import qualified Data.List.NonEmpty as NE
import Monad.Rail.Error
import Monad.Rail.Types
import Test.Hspec

-- ---------------------------------------------------------------------------
-- Test fixtures
-- ---------------------------------------------------------------------------

data TestError = ErrA | ErrB | ErrC
  deriving (Show, Eq)

instance HasErrorInfo TestError where
  errorInfo ErrA =
    ErrorInfo
      { publicMessage = "Error A",
        internalMessage = Nothing,
        code = "ERR_A",
        severity = Error,
        exception = Nothing,
        details = Nothing
      }
  errorInfo ErrB =
    ErrorInfo
      { publicMessage = "Error B",
        internalMessage = Nothing,
        code = "ERR_B",
        severity = Error,
        exception = Nothing,
        details = Nothing
      }
  errorInfo ErrC =
    ErrorInfo
      { publicMessage = "Error C",
        internalMessage = Nothing,
        code = "ERR_C",
        severity = Error,
        exception = Nothing,
        details = Nothing
      }

throw :: TestError -> Rail ()
throw e = throwError (ApplicationError e)

-- ---------------------------------------------------------------------------
-- Spec
-- ---------------------------------------------------------------------------

spec :: Spec
spec = do
  describe "runRail" $ do
    it "returns Right for a successful computation" $ do
      result <- runRail (pure "hello")
      case result of
        Left _ -> expectationFailure "expected Right, got Left"
        Right val -> val `shouldBe` ("hello" :: String)

    it "returns Right () for a unit computation" $ do
      result <- runRail (pure ())
      case result of
        Left _ -> expectationFailure "expected Right, got Left"
        Right () -> pure ()

    it "can run IO actions via liftIO" $ do
      result <- runRail $ liftIO (pure 42 :: IO Int)
      case result of
        Left _ -> expectationFailure "expected Right, got Left"
        Right val -> val `shouldBe` (42 :: Int)

  describe "throwError" $ do
    it "returns Left with a single error" $ do
      result <- runRail (throw ErrA)
      case result of
        Right _ -> expectationFailure "expected Left, got Right"
        Left err -> length (getAppErrors err) `shouldBe` 1

    it "the error carries the correct code" $ do
      result <- runRail (throw ErrA)
      case result of
        Right _ -> expectationFailure "expected Left, got Right"
        Left err ->
          let info = errorInfo (NE.head (getAppErrors err))
           in code info `shouldBe` "ERR_A"

    it "short-circuits: code after throwError is not executed" $ do
      ref <- newIORef (0 :: Int)
      _ <- runRail $ do
        throw ErrA
        liftIO $ modifyIORef ref (+ 1)
      val <- readIORef ref
      val `shouldBe` 0

  describe "<!> (error accumulation operator)" $ do
    describe "Right <!> Right" $ do
      it "succeeds when both validations pass" $ do
        result <- runRail (pure () <!> pure ())
        case result of
          Left _ -> expectationFailure "expected Right, got Left"
          Right () -> pure ()

    describe "Left <!> Right" $ do
      it "fails with the first error only" $ do
        result <- runRail (throw ErrA <!> pure ())
        case result of
          Right _ -> expectationFailure "expected Left, got Right"
          Left err -> do
            length (getAppErrors err) `shouldBe` 1
            (code . errorInfo . NE.head . getAppErrors) err `shouldBe` "ERR_A"

    describe "Right <!> Left" $ do
      it "fails with the second error only" $ do
        result <- runRail (pure () <!> throw ErrB)
        case result of
          Right _ -> expectationFailure "expected Left, got Right"
          Left err -> do
            length (getAppErrors err) `shouldBe` 1
            (code . errorInfo . NE.head . getAppErrors) err `shouldBe` "ERR_B"

    describe "Left <!> Left" $ do
      it "accumulates errors from both sides" $ do
        result <- runRail (throw ErrA <!> throw ErrB)
        case result of
          Right _ -> expectationFailure "expected Left, got Right"
          Left err -> length (getAppErrors err) `shouldBe` 2

      it "preserves left error before right error" $ do
        result <- runRail (throw ErrA <!> throw ErrB)
        case result of
          Right _ -> expectationFailure "expected Left, got Right"
          Left err ->
            let codes = map (code . errorInfo) (NE.toList (getAppErrors err))
             in codes `shouldBe` ["ERR_A", "ERR_B"]

    describe "chaining three validations" $ do
      it "accumulates all three errors when all fail" $ do
        result <- runRail (throw ErrA <!> throw ErrB <!> throw ErrC)
        case result of
          Right _ -> expectationFailure "expected Left, got Right"
          Left err -> length (getAppErrors err) `shouldBe` 3

      it "accumulates errors from two failing and one passing" $ do
        result <- runRail (throw ErrA <!> pure () <!> throw ErrC)
        case result of
          Right _ -> expectationFailure "expected Left, got Right"
          Left err -> length (getAppErrors err) `shouldBe` 2

      it "succeeds when all three pass" $ do
        result <- runRail (pure () <!> pure () <!> pure ())
        case result of
          Left _ -> expectationFailure "expected Right, got Left"
          Right () -> pure ()

    describe "continuation after <!>" $ do
      it "does not execute subsequent do-block actions when errors accumulated" $ do
        ref <- newIORef (0 :: Int)
        _ <- runRail $ do
          throw ErrA <!> throw ErrB
          liftIO $ modifyIORef ref (+ 1)
        val <- readIORef ref
        val `shouldBe` 0

      it "does execute subsequent do-block actions when all pass" $ do
        ref <- newIORef (0 :: Int)
        _ <- runRail $ do
          pure () <!> pure ()
          liftIO $ modifyIORef ref (+ 1)
        val <- readIORef ref
        val `shouldBe` 1

  describe "tryRail" $ do
    it "returns Right when the IO action succeeds" $ do
      result <- runRail (tryRail (pure (42 :: Int)))
      case result of
        Left _    -> expectationFailure "expected Right, got Left"
        Right val -> val `shouldBe` 42

    it "returns Left when the IO action throws" $ do
      let boom = Ex.throwIO (userError "oops")
      result <- runRail (tryRail boom :: Rail ())
      case result of
        Right _ -> expectationFailure "expected Left, got Right"
        Left _  -> pure ()

    it "wraps the exception as a single UNCAUGHT_EXCEPTION error" $ do
      let boom = Ex.throwIO (userError "oops")
      result <- runRail (tryRail boom :: Rail ())
      case result of
        Right _ -> expectationFailure "expected Left, got Right"
        Left err -> do
          let errs = getAppErrors err
          length errs `shouldBe` 1
          (code . errorInfo . NE.head) errs `shouldBe` "UNCAUGHT_EXCEPTION"

    it "the error has Critical severity" $ do
      let boom = Ex.throwIO (userError "oops")
      result <- runRail (tryRail boom :: Rail ())
      case result of
        Right _ -> expectationFailure "expected Left, got Right"
        Left err ->
          (severity . errorInfo . NE.head . getAppErrors) err `shouldBe` Critical

    it "preserves the original exception in the error" $ do
      let boom = Ex.throwIO (userError "original message")
      result <- runRail (tryRail boom :: Rail ())
      case result of
        Right _ -> expectationFailure "expected Left, got Right"
        Left err ->
          let info = (errorInfo . NE.head . getAppErrors) err
          in exception info `shouldSatisfy` maybe False (("original message" `isInfixOf`) . show)

    it "short-circuits: code after tryRail failure is not executed" $ do
      ref <- newIORef (0 :: Int)
      let boom = Ex.throwIO (userError "fail")
      _ <- runRail $ do
        _ <- tryRail (boom :: IO Int)
        liftIO $ modifyIORef ref (+ 1)
      val <- readIORef ref
      val `shouldBe` 0

    it "can be combined with <!>" $ do
      let boom = Ex.throwIO (userError "io fail")
      result <- runRail (tryRail (boom :: IO ()) <!> throw ErrA)
      case result of
        Right _ -> expectationFailure "expected Left, got Right"
        Left err -> length (getAppErrors err) `shouldBe` 2
