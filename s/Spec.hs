{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Main where

import Data.Aeson
import GHC.Generics
import Test.QuickCheck
import Test.QuickCheck.Monadic
import System.Process (readProcess)
import qualified Data.Map.Strict as M
import qualified Data.ByteString.Lazy.Char8 as LBS

data Op
  = CreateState Int Int
  | CreateCompute Int [Int]
  | WriteState Int Int
  | Flush
  deriving (Show, Eq, Generic)

instance ToJSON Op where
  toJSON (CreateState nId v)   = object ["type" .= ("createState" :: String), "id" .= nId, "value" .= v]
  toJSON (CreateCompute nId ds) = object ["type" .= ("createCompute" :: String), "id" .= nId, "deps" .= ds]
  toJSON (WriteState nId v)    = object ["type" .= ("write" :: String), "id" .= nId, "value" .= v]
  toJSON Flush                 = object ["type" .= ("flush" :: String)]

data JSSnapshot = JSSnapshot
  { hasError        :: Bool
  , errorMsg        :: String
  , values          :: M.Map String Int
  , flushDurationMs :: Double
  } deriving (Show, Eq, Generic)

instance FromJSON JSSnapshot

data NodeDef = StateDef Int | ComputeDef [Int] deriving (Show, Eq)

data Model = Model
  { defs :: M.Map Int NodeDef
  , vals :: M.Map Int Int
  } deriving (Show, Eq)

evalCompute :: M.Map Int Int -> [Int] -> Int
evalCompute currentVals deps = sum [ M.findWithDefault 0 d currentVals | d <- deps ]

recomputeAll :: Model -> Model
recomputeAll (Model d v) = Model d (M.foldlWithKey updateVal v d)
  where
    updateVal acc nId (ComputeDef deps) = M.insert nId (evalCompute acc deps) acc
    updateVal acc _     (StateDef _)    = acc

step :: Model -> Op -> Model
step (Model d v) (CreateState i val) =
  Model (M.insert i (StateDef val) d) (M.insert i val v)
step (Model d v) (CreateCompute i deps) =
  let initialVal = evalCompute v deps
  in Model (M.insert i (ComputeDef deps) d) (M.insert i initialVal v)
step (Model d v) (WriteState i val) =
  Model d (M.insert i val v)
step m Flush = recomputeAll m

simulateHaskell :: [Op] -> M.Map String Int
simulateHaskell ops =
  let finalModel = recomputeAll $ foldl step (Model M.empty M.empty) ops
  in M.mapKeys show (vals finalModel)

data ValidOpSequence = ValidOpSequence [Op] deriving (Show)

instance Arbitrary ValidOpSequence where
  arbitrary = do
    
    nodeCount <- choose (10, 30)
    (setupOps, stateIds) <- genNodes 0 nodeCount [] []
    
    mutations <- genMutations stateIds 1000
    return $ ValidOpSequence (setupOps ++ mutations)
    where
      genNodes current maxCount createdIds stateIds
        | current >= maxCount = return ([], stateIds)
        | otherwise = do
            isState <- if null createdIds then return True else arbitrary
            if isState
              then do
                val <- choose (1, 100)
                (rest, restStates) <- genNodes (current + 1) maxCount (current : createdIds) (current : stateIds)
                return (CreateState current val : rest, restStates)
              else do
                deps <- sublistOf createdIds
                (rest, restStates) <- genNodes (current + 1) maxCount (current : createdIds) stateIds
                return (CreateCompute current deps : rest, restStates)

      genMutations [] _ = return []
      genMutations stateIds n
        | n <= 0 = return []
        | otherwise = do
            isWrite <- choose (1 :: Int, 4)
            if isWrite > 1
              then do
                targetState <- elements stateIds
                val <- choose (1, 100)
                rest <- genMutations stateIds (n - 1)
                return (WriteState targetState val : rest)
              else do
                rest <- genMutations stateIds (n - 1)
                return (Flush : rest)

prop_waterveinMatchesModel :: ValidOpSequence -> Property
prop_waterveinMatchesModel (ValidOpSequence ops) = monadicIO $ do
  let jsonInput = LBS.unpack (encode ops)
  rawOutput <- run $ readProcess "npx" ["vite-node", "runner.mjs", jsonInput] ""
  case decode (LBS.pack rawOutput) of
    Nothing -> fail $ "Failed to parse JS output: " ++ rawOutput
    Just jsResult -> do
      let expectedValues = simulateHaskell ops
      
      
      monitor (counterexample $ "JS Error: " ++ errorMsg jsResult)
      assert (not (hasError jsResult))
      
      
      monitor (counterexample $ "Expected: " ++ show expectedValues ++ "\nGot: " ++ show (values jsResult))
      assert (values jsResult == expectedValues)

main :: IO ()
main = quickCheckWith (stdArgs { maxSuccess = 100 }) prop_waterveinMatchesModel