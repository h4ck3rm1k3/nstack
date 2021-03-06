module NStack.Prelude.Exception
  ( TransientError(..)
  , throwTransientError
  , throwTransientErrorT
  , PermanentError(..)
  , throwPermanentError
  , throwPermanentErrorT
  )
  where

import Control.Exception
import Data.Text (unpack, Text)
import Data.Typeable (Typeable)
import Control.Monad.IO.Class (MonadIO(..))

data TransientError = TransientError String
  deriving (Show, Typeable)

instance Exception TransientError where
  displayException (TransientError msg) = msg

-- | A shortcut for commonly-occurring @liftIO . throwIO . PermanentError@.
throwTransientError :: MonadIO m => String -> m a
throwTransientError = liftIO . throwIO . TransientError

throwTransientErrorT :: MonadIO m => Text -> m a
throwTransientErrorT = throwTransientError . unpack

data PermanentError = PermanentError String
  deriving (Show, Typeable)

instance Exception PermanentError where
  displayException (PermanentError msg) = msg

-- | A shortcut for commonly-occurring @liftIO . throwIO . PermanentError@.
throwPermanentError :: MonadIO m => String -> m a
throwPermanentError = liftIO . throwIO . PermanentError

throwPermanentErrorT :: MonadIO m => Text -> m a
throwPermanentErrorT = throwPermanentError . unpack
