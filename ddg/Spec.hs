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
  | CreateDynamicCompute { nId :: Int, condId :: Int, thenId :: Int, elseId :: Int }
  | WriteState Int Int
  | Flush
  deriving (Show, Eq, Generic)

instance ToJSON Op where
  toJSON (CreateState i v) =
    object ["type" .= ("createState" :: String), "id" .= i, "value" .= v]
  toJSON (CreateDynamicCompute i c t e) =
    object ["type" .= ("createDynamicCompute" :: String), "id" .= i, "conditionId" .= c, "thenId" .= t, "elseId" .= e]
  toJSON (WriteState i v) =
    object ["type" .= ("write" :: String), "id" .= i, "value" .= v]
  toJSON Flush =
    object ["type" .= ("flush" :: String)]

data JSSnapshot = JSSnapshot
  { hasError   :: Bool
  , errorMsg   :: String
  , values     :: M.Map String Int
  , evalCounts :: M.Map String Int
  } deriving (Show, Eq, Generic)

instance FromJSON JSSnapshot

data NodeDef
  = StateDef Int
  | DynamicComputeDef { cond :: Int, thenBranch :: Int, elseBranch :: Int }
  deriving (Show, Eq)

data Model = Model
  { defs :: M.Map Int NodeDef
  , vals :: M.Map Int Int
  } deriving (Show, Eq)

evalNode :: M.Map Int Int -> NodeDef -> Int
evalNode currentVals (StateDef v) = v
evalNode currentVals (DynamicComputeDef c t e) =
  let cVal = M.findWithDefault 0 c currentVals
  in if cVal /= 0
       then M.findWithDefault 0 t currentVals
       else M.findWithDefault 0 e currentVals

recomputeAll :: Model -> Model
recomputeAll (Model d v) = Model d (M.foldlWithKey updateVal v d)
  where
    updateVal acc i nodeDef = M.insert i (evalNode acc nodeDef) acc

step :: Model -> Op -> Model
step (Model d v) (CreateState i val) =
  Model (M.insert i (StateDef val) d) (M.insert i val v)
step (Model d v) (CreateDynamicCompute i c t e) =
  let nodeDef = DynamicComputeDef c t e
      initialVal = evalNode v nodeDef
  in Model (M.insert i nodeDef d) (M.insert i initialVal v)
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
    stateCount <- choose (3, 5)
    computeCount <- choose (2, 4)
    
    let stateOps = [ CreateState i (i * 10) | i <- [0 .. stateCount - 1] ]
    let stateIds = [0 .. stateCount - 1]
    
    let computeOps = [ CreateDynamicCompute (stateCount + i) 
                        (i `mod` stateCount) 
                        ((i + 1) `mod` stateCount) 
                        ((i + 2) `mod` stateCount) 
                     | i <- [0 .. computeCount - 1] ]

    mutations <- vectorOf 50 $ do
      isWrite <- arbitrary
      if isWrite
        then do
          target <- elements stateIds
          val <- choose (0, 1)
          return $ WriteState target val
        else return Flush
        
    return $ ValidOpSequence (stateOps ++ computeOps ++ mutations)

  shrink (ValidOpSequence ops) =
    let (setup, mutations) = span isCreate ops
    in [ ValidOpSequence (setup ++ m') | m' <- shrinkList (const []) mutations, not (null m') ]
    where
      isCreate (CreateState _ _) = True
      isCreate (CreateDynamicCompute {}) = True
      isCreate _ = False

prop_dynamicGraphMatchesModel :: ValidOpSequence -> Property
prop_dynamicGraphMatchesModel (ValidOpSequence ops) = monadicIO $ do
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
main = quickCheckWith (stdArgs { maxSuccess = 100 }) prop_dynamicGraphMatchesModel