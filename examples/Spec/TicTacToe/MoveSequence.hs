module Spec.TicTacToe.MoveSequence (
  moveSequencePermutationGenSelfTest,
) where

import Apropos.Gen
import Apropos.HasLogicalModel
import Apropos.HasParameterisedGenerator
import Apropos.HasPermutationGenerator
import Apropos.HasPermutationGenerator.Contract
import Apropos.LogicalModel
import Control.Monad (join)
import Data.Hashable (Hashable)
import Data.List (transpose)
import Data.Set (Set)
import Data.Set qualified as Set
import GHC.Generics (Generic)
import Spec.TicTacToe.LocationSequence
import Test.Tasty (TestTree, testGroup)
import Test.Tasty.Hedgehog (fromGroup)

data MoveSequenceProperty
  = MoveSequenceValid
  | MoveSequenceContainsWin
  deriving stock (Eq, Ord, Show, Generic)
  deriving anyclass (Enumerable, Hashable)

splitPlayers :: [Int] -> ([Int], [Int])
splitPlayers locationSeq = go locationSeq ([], [])
  where
    go [] p = p
    go [s] (a, b) = (s : a, b)
    go (h : i : j) (a, b) = go j (h : a, i : b)

containsWin :: [Int] -> Bool
containsWin locationSeq =
  let (x, o) = splitPlayers locationSeq
   in any (all (`elem` x)) winTileSets || any (all (`elem` o)) winTileSets

winTileSets :: [Set Int]
winTileSets =
  Set.fromList
    <$> [ [0, 1, 2]
        , [3, 4, 5]
        , [6, 7, 8]
        , [0, 3, 6]
        , [1, 4, 7]
        , [2, 5, 8]
        , [0, 4, 8]
        , [2, 4, 6]
        ]

instance LogicalModel MoveSequenceProperty where
  logic = Yes

locationSequenceIsValid :: Formula LocationSequenceProperty
locationSequenceIsValid =
  Var AllLocationsAreInBounds
    :&&: Not (Var SomeLocationIsOccupiedTwice)

instance HasLogicalModel MoveSequenceProperty [Int] where
  satisfiesProperty MoveSequenceValid ms = satisfiesExpression locationSequenceIsValid ms
  satisfiesProperty MoveSequenceContainsWin ms = containsWin ms

baseGen :: Gen [Int]
baseGen = genSatisfying (Yes :: Formula LocationSequenceProperty)

instance HasPermutationGenerator MoveSequenceProperty [Int] where
  generators =
    [ Morphism
        { name = "InvalidNoWin"
        , match = Yes
        , contract = clear
        , morphism = \_ ->
            genFilter (not . containsWin) $
              genSatisfying $ Not locationSequenceIsValid
        }
    , Morphism
        { name = "ValidNoWin"
        , match = Yes
        , contract = clear >> add MoveSequenceValid
        , morphism = \_ ->
            genFilter (not . containsWin) $
              genSatisfying locationSequenceIsValid
        }
    , Morphism
        { name = "InvalidWin"
        , match = Not $ Var MoveSequenceValid
        , contract = add MoveSequenceContainsWin
        , morphism = \moves -> genFilter
            ( \w ->
                containsWin w
                  && satisfiesExpression (Not locationSequenceIsValid) w
            )
            $ do
              if length moves < 2
                then retry
                else do
                  winlocs <- Set.toList <$> element winTileSets
                  whofirst <- element [[moves, winlocs], [winlocs, moves]]
                  pure $ join $ transpose whofirst
        }
    , Morphism
        { name = "ValidWin"
        , match = Var MoveSequenceValid
        , contract = add MoveSequenceContainsWin
        , morphism = \moves -> do
            winlocs <- Set.toList <$> element (errLabelWhenNull "1" winTileSets)
            whofirst <- element $ errLabelWhenNull "2" [[moves, winlocs], [winlocs, moves]]
            let win = join $ transpose whofirst
            if containsWin win && satisfiesExpression locationSequenceIsValid win
              then pure win
              else retry
        }
    ]

errLabelWhenNull :: String -> [a] -> [a]
errLabelWhenNull la li = if null li then error la else li

instance HasParameterisedGenerator MoveSequenceProperty [Int] where
  parameterisedGenerator = buildGen baseGen

moveSequencePermutationGenSelfTest :: TestTree
moveSequencePermutationGenSelfTest =
  testGroup "moveSequencePermutationGenSelfTest" $
    fromGroup
      <$> permutationGeneratorSelfTest
        True
        (\(_ :: Morphism MoveSequenceProperty [Int]) -> True)
        baseGen
