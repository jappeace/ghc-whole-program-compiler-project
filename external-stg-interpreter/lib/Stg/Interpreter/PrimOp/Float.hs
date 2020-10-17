{-# LANGUAGE RecordWildCards, LambdaCase, OverloadedStrings, PatternSynonyms #-}
module Stg.Interpreter.PrimOp.Float where

import Stg.Syntax
import Stg.Interpreter.Base

pattern IntV i    = Literal (LitNumber LitNumInt i)
pattern FloatV f  = FloatAtom f
pattern DoubleV d = DoubleAtom d

evalPrimOp :: PrimOpEval -> Name -> [Atom] -> Type -> Maybe TyCon -> M [Atom]
evalPrimOp fallback op args t tc = case (op, args) of

  -- gtFloat# :: Float# -> Float# -> Int#
  ("gtFloat#",      [FloatV a, FloatV b]) -> pure [IntV $ if a > b  then 1 else 0]

  -- geFloat# :: Float# -> Float# -> Int#
  ("geFloat#",      [FloatV a, FloatV b]) -> pure [IntV $ if a >= b then 1 else 0]

  -- eqFloat# :: Float# -> Float# -> Int#
  ("eqFloat#",      [FloatV a, FloatV b]) -> pure [IntV $ if a == b then 1 else 0]

  -- neFloat# :: Float# -> Float# -> Int#
  ("neFloat#",      [FloatV a, FloatV b]) -> pure [IntV $ if a /= b then 1 else 0]

  -- ltFloat# :: Float# -> Float# -> Int#
  ("ltFloat#",      [FloatV a, FloatV b]) -> pure [IntV $ if a < b  then 1 else 0]

  -- leFloat# :: Float# -> Float# -> Int#
  ("leFloat#",      [FloatV a, FloatV b]) -> pure [IntV $ if a <= b then 1 else 0]

  -- plusFloat# :: Float# -> Float# -> Float#
  ("plusFloat#",    [FloatV a, FloatV b]) -> pure [FloatV $ a + b]

  -- minusFloat# :: Float# -> Float# -> Float#
  ("minusFloat#",   [FloatV a, FloatV b]) -> pure [FloatV $ a - b]

  -- timesFloat# :: Float# -> Float# -> Float#
  ("timesFloat#",   [FloatV a, FloatV b]) -> pure [FloatV $ a * b]

  -- divideFloat# :: Float# -> Float# -> Float#
  ("divideFloat#",  [FloatV a, FloatV b]) -> pure [FloatV $ a / b]

  -- negateFloat# :: Float# -> Float#
  ("negateFloat#",  [FloatV a]) -> pure [FloatV (-a)]

  -- fabsFloat# :: Float# -> Float#
  ("fabsFloat#",    [FloatV a]) -> pure [FloatV (abs a)]

  -- float2Int# :: Float# -> Int#
  ("float2Int#",    [FloatV a]) -> pure [IntV $ truncate a]

  -- expFloat# :: Float# -> Float#
  ("expFloat#",     [FloatV a]) -> pure [FloatV $ exp a]

  -- TODO: expm1Float# :: Float# -> Float#

  -- logFloat# :: Float# -> Float#
  ("logFloat#",     [FloatV a]) -> pure [FloatV $ log a]

  -- TODO: log1pFloat# :: Float# -> Float#

  -- sqrtFloat# :: Float# -> Float#
  ("sqrtFloat#",    [FloatV a]) -> pure [FloatV $ sqrt a]

  -- sinFloat# :: Float# -> Float#
  ("sinFloat#",     [FloatV a]) -> pure [FloatV $ sin a]

  -- cosFloat# :: Float# -> Float#
  ("cosFloat#",     [FloatV a]) -> pure [FloatV $ cos a]

  -- tanFloat# :: Float# -> Float#
  ("FloatV",        [FloatV a]) -> pure [FloatV $ tan a]

  -- asinFloat# :: Float# -> Float#
  ("FloatV",        [FloatV a]) -> pure [FloatV $ asin a]

  -- acosFloat# :: Float# -> Float#
  ("FloatV",        [FloatV a]) -> pure [FloatV $ acos a]

  -- atanFloat# :: Float# -> Float#
  ("FloatV",        [FloatV a]) -> pure [FloatV $ atan a]

  -- sinhFloat# :: Float# -> Float#
  ("FloatV",        [FloatV a]) -> pure [FloatV $ sinh a]

  -- coshFloat# :: Float# -> Float#
  ("FloatV",        [FloatV a]) -> pure [FloatV $ cosh a]

  -- tanhFloat# :: Float# -> Float#
  ("FloatV",        [FloatV a]) -> pure [FloatV $ tanh a]

  -- TODO: asinhFloat# :: Float# -> Float#
  -- TODO: acoshFloat# :: Float# -> Float#
  -- TODO: atanhFloat# :: Float# -> Float#

  -- powerFloat# :: Float# -> Float# -> Float#
  ("powerFloat#",   [FloatV a, FloatV b]) -> pure [FloatV $ a ** b]

  -- float2Double# ::  Float# -> Double#
  ("float2Double#", [FloatV a]) -> pure [DoubleV $ realToFrac a]

  -- TODO: decodeFloat_Int# :: Float# -> (# Int#, Int# #)

  _ -> fallback op args t tc