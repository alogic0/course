{-# LANGUAGE NoImplicitPrelude #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE InstanceSigs #-}
{-# LANGUAGE RebindableSyntax #-}

module Course.State where

import Course.Core
import qualified Prelude as P
import Course.Optional
import Course.List
import Course.Functor
import Course.Apply
import Course.Applicative
import Course.Bind
import Course.Monad
import qualified Data.Set as S

-- $setup
-- >>> import Test.QuickCheck.Function
-- >>> import Data.List(nub)
-- >>> import Test.QuickCheck
-- >>> import qualified Prelude as P(fmap)
-- >>> import Course.Core
-- >>> import Course.List
-- >>> instance Arbitrary a => Arbitrary (List a) where arbitrary = P.fmap listh arbitrary

-- A `State` is a function from a state value `s` to (a produced value `a`, and a resulting state `s`).
newtype State s a =
  State {
    runState ::
      s
      -> (a, s)
  }

-- | Implement the `Functor` instance for `State s`.
-- >>> runState ((+1) <$> pure 0) 0
-- (1,0)
instance Functor (State s) where
  (<$>) ::
    (a -> b)
    -> State s a
    -> State s b
  (<$>) f st =
      State $ \s -> let (a1, s1) = runState st s in (f a1, s1)

-- | Implement the `Apply` instance for `State s`.
-- >>> runState (pure (+1) <*> pure 0) 0
-- (1,0)
--
-- >>> import qualified Prelude as P
-- >>> runState (State (\s -> ((+3), s P.++ ["apple"])) <*> State (\s -> (7, s P.++ ["banana"]))) []
-- (10,["apple","banana"])
instance Apply (State s) where
  (<*>) ::
    State s (a -> b)
    -> State s a
    -> State s b 
  (<*>) stf sta =
    State $ \s -> let (f, s1) = runState stf s in runState (f <$> sta) s1 

-- | Implement the `Applicative` instance for `State s`.
-- >>> runState (pure 2) 0
-- (2,0)
instance Applicative (State s) where
  pure ::
    a
    -> State s a
  pure a = State $ \s -> (a, s)

-- | Implement the `Bind` instance for `State s`.
-- >>> runState ((const $ put 2) =<< put 1) 0
-- ((),2)
instance Bind (State s) where
  (=<<) ::
    (a -> State s b)
    -> State s a
    -> State s b
  (=<<) f sta =
    State $ \s -> let (a1, s1) = runState sta s
		  in runState (f a1) s1

instance Monad (State s) where

-- | Run the `State` seeded with `s` and retrieve the resulting state.
--
-- prop> \(Fun _ f) -> exec (State f) s == snd (runState (State f) s)
exec ::
  State s a
  -> s
  -> s
exec st = snd . runState st

-- | Run the `State` seeded with `s` and retrieve the resulting value.
--
-- prop> \(Fun _ f) -> eval (State f) s == fst (runState (State f) s)
eval ::
  State s a
  -> s
  -> a
eval st = fst . runState st

-- | A `State` where the state also distributes into the produced value.
--
-- >>> runState get 0
-- (0,0)
get ::
  State s s
get = State $ \s -> (s, s)

-- | A `State` where the resulting state is seeded with the given value.
--
-- >>> runState (put 1) 0
-- ((),1)
put ::
  s
  -> State s ()
put x = State $ \_ -> ((), x) 

-- | Find the first element in a `List` that satisfies a given predicate.
-- It is possible that no element is found, hence an `Optional` result.
-- However, while performing the search, we sequence some `Monad` effect through.
--
-- Note the similarity of the type signature to List#find
-- where the effect appears in every return position:
--   find ::  (a ->   Bool) -> List a ->    Optional a
--   findM :: (a -> f Bool) -> List a -> f (Optional a)
--
-- >>> let p x = (\s -> (const $ pure (x == 'c')) =<< put (1+s)) =<< get in runState (findM p $ listh ['a'..'h']) 0
-- (Full 'c',3)
--
-- >>> let p x = (\s -> (const $ pure (x == 'i')) =<< put (1+s)) =<< get in runState (findM p $ listh ['a'..'h']) 0
-- (Empty,8)
findM ::
  Monad f =>
  (a -> f Bool)
  -> List a
  -> f (Optional a)
findM p xs =
    case xs of
      Nil -> return Empty
      (x :. xs') -> do b <- p x
                       if b
                       then return (Full x)
                       else findM p xs'

-- | Find the first element in a `List` that repeats.
-- It is possible that no element repeats, hence an `Optional` result.
--
-- /Tip:/ Use `findM` and `State` with a @Data.Set#Set@.
--
-- prop> case firstRepeat xs of Empty -> let xs' = hlist xs in nub xs' == xs'; Full x -> length (filter (== x) xs) > 1
-- prop> case firstRepeat xs of Empty -> True; Full x -> let (l, (rx :. rs)) = span (/= x) xs in let (l2, r2) = span (/= x) rs in let l3 = hlist (l ++ (rx :. Nil) ++ l2) in nub l3 == l3
firstRepeat ::
  Ord a =>
  List a
  -> Optional a
firstRepeat xs =
  let p x = do s <- get
               put $ S.insert x s
               return (S.member x s) 
  in fst $ runState (findM p xs) S.empty

-- | Remove all duplicate elements in a `List`.
-- /Tip:/ Use `filtering` and `State` with a @Data.Set#Set@.
--
-- prop> firstRepeat (distinct xs) == Empty
--
-- prop> distinct xs == distinct (flatMap (\x -> x :. x :. Nil) xs)
distinct ::
  Ord a =>
  List a
  -> List a
distinct xs =
  let p x = do s <- get
               put $ S.insert x s
               return (S.notMember x s) 
  in fst $ runState (filtering p xs) S.empty

-- | A happy number is a positive integer, where the sum of the square of its digits eventually reaches 1 after repetition.
-- In contrast, a sad number (not a happy number) is where the sum of the square of its digits never reaches 1
-- because it results in a recurring sequence.
--
-- /Tip:/ Use `findM` with `State` and `produce`.
--
-- /Tip:/ Use `flatten` to write a @square@ function.
--
-- /Tip:/ Use library functions: @Optional#contains@, @Data.Char#digitToInt@.
--
-- >>> isHappy 4
-- False
--
-- >>> isHappy 7
-- True
--
-- >>> isHappy 42
-- False
--
-- >>> isHappy 44
-- True
isHappy ::
  Integer
  -> Bool
isHappy num =
    contains 1 $ firstRepeat $ happyList num

-- for playing with
square :: forall a. Num a => a -> a
square x = x * x

happySum :: forall a. Show a => a -> Int
happySum n = sum $ map (square . digitToInt) $ show' n

happyList :: forall a. Show a => a -> List Int
happyList n = produce happySum (happySum n)

sortL :: Ord t => List t -> List t
sortL Nil = Nil
sortL (x :. xs) = sortL (filter (< x) xs) ++ (x :. Nil) ++ sortL (filter (x <=) xs)

happyDistinct :: List Integer -> List (List Char)
happyDistinct xs = distinct $  map (sortL . filter (/= '0') . show') $ filter isHappy xs
