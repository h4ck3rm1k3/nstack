{-# LANGUAGE TemplateHaskell #-}

module NStack.Module.Types (module NStack.Module.Types) where
import Control.Lens (Lens', iso, Iso')   -- from: lens
import Data.ByteString (ByteString)
import qualified Data.ByteString as BS
import qualified Data.ByteString.Base16 as Base16
import Data.Coerce (coerce)
import Data.SafeCopy (base, deriveSafeCopy, extension, Migrate(..), SafeCopy(..), safePut, safeGet, contain)
import Data.Monoid ((<>))
import Data.Serialize (Serialize(..))
import Data.Serialize.Get (getListOf)
import Data.Serialize.Put (putListOf)
import Data.String (IsString)
import Data.Text (Text)                        -- from: text
import qualified Data.Text as T                -- from: text
import Data.Aeson (ToJSON(..), FromJSON(..), ToJSONKey, FromJSONKey)
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Typeable (Typeable)
import Data.Data (Data(..))
import Data.UUID (UUID)
import GHC.Generics (Generic)
import Text.PrettyPrint.Mainland (Pretty, ppr, text, commasep, char, integer)   -- from: mainland-pretty
import Text.Printf (printf)

import NStack.Auth (UserName(..), nstackUserName)
import NStack.SafeCopyOrphans ()
import NStack.UUIDOrphans ()
import NStack.Prelude.Text (showT, putText, getText, pprS)

type APIVersion = Integer

data Language = Python | Python2 | NodeJS | Haskell | R
  deriving (Show, Eq, Ord, Generic)

data Stack = Stack Language APIVersion
  deriving (Show, Eq, Ord, Generic)

instance Serialize Language
$(deriveSafeCopy 0 'base ''Language)

instance Serialize Stack
$(deriveSafeCopy 0 'base ''Stack)

instance Pretty Language where
  ppr = text . show

instance Pretty Stack where
  ppr (Stack l v) = ppr l <> char '-' <> integer v

newtype NSUri = NSUri { _nsUri :: [Text] }
  deriving (Eq, Ord, Typeable, Data, Generic)

instance ToJSON NSUri
instance FromJSON NSUri

instance Show NSUri where
  show = T.unpack . T.intercalate "." . _nsUri

instance Serialize NSUri where
  put = coerce (putListOf putText)
  get = coerce (getListOf getText)

$(deriveSafeCopy 0 'base ''NSUri)

newtype Author = Author Text

instance Serialize Author where
  put = coerce putText
  get = coerce getText

data Version_v0 = Version_v0 Integer Integer Integer
data Version_v1 = Version_v1 Integer Integer Integer Bool

-- The order of constructors is significant for the Ord instance
data Release = Snapshot | Release
  deriving (Eq, Ord, Show, Generic, Typeable, Data)

instance ToJSON Release
instance FromJSON Release

-- TODO add version helper funcs that support semver?
data Version = Version {
  _majorVer :: Integer,
  _minorVer :: Integer,
  _patchVer :: Integer,
  _release  :: Release
} deriving (Eq, Ord, Generic, Typeable, Data)

instance ToJSON Version
instance FromJSON Version

instance Migrate Version_v1 where
  type MigrateFrom Version_v1 = Version_v0
  migrate (Version_v0 a b c) = Version_v1 a b c True
instance Migrate Version where
  type MigrateFrom Version = Version_v1
  migrate (Version_v1 a b c isRelease) = Version a b c $
    if isRelease then Release else Snapshot

instance Show Version where
  show (Version ma mi p r) =
    show ma <> "." <> show mi <> "." <> show p <>
      case r of
        Release -> ""
        Snapshot -> "-SNAPSHOT"

initVersion :: Version
initVersion = Version 0 0 1 Snapshot

data ModuleName_v0 = MN0 NSUri Author NSUri Version
  deriving (Generic)

-- | Name for a unique module that exists on the server
data ModuleName = ModuleName {
  _mRegistry :: NSUri,
  _mAuthor :: UserName,
  _mName :: NSUri,
  _mVersion :: Version
} deriving (Show, Eq, Ord, Generic, Typeable, Data)

instance Pretty ModuleName where
  ppr = text . showShortModuleName

nStackRegistry :: NSUri
nStackRegistry = NSUri ["registry", "nstack", "com"]

-- | Helper function to create a ModuleName using the default registry/author
mkNStackModuleName :: NSUri -> Version -> ModuleName
mkNStackModuleName = ModuleName nStackRegistry nstackUserName

type FedoraVersion = Integer
type FedoraSnapshot = Integer

-- | Make an NStack module name used internally for base images by the system
mkBaseModuleName :: Text -> APIVersion -> FedoraVersion -> FedoraSnapshot -> ModuleName
mkBaseModuleName s v majS minS = mkNStackModuleName (NSUri ["NStack", s]) (Version majS minS v Release)

-- | display the module name, hiding registry and author if they are the default
showShortModuleName :: ModuleName -> String
showShortModuleName ModuleName{..} = T.unpack $ reg <> aut <> showT _mName <> ":" <> showT _mVersion
  where
    reg = if _mRegistry == nStackRegistry then "" else showT _mRegistry <> "/"
    -- changing to always show author for now, rather than hiding if aut == nStackAuthor
    aut = _username _mAuthor <> "/"


instance Serialize Release
instance Serialize Version
instance Serialize ModuleName_v0
instance Serialize ModuleName

$(deriveSafeCopy 0 'base ''Author)
$(deriveSafeCopy 0 'base ''Release)
$(deriveSafeCopy 0 'base ''Version_v0)
$(deriveSafeCopy 1 'extension ''Version_v1)
$(deriveSafeCopy 2 'extension ''Version)
$(deriveSafeCopy 0 'base ''ModuleName_v0)
$(deriveSafeCopy 1 'extension ''ModuleName)

instance Migrate ModuleName where
  type MigrateFrom ModuleName = ModuleName_v0
  migrate (MN0 n (Author t) n' v) = ModuleName n (UserName t) n' v

-- | The name of an NStack function
newtype FnName = FnName Text
  deriving (Eq, Ord, Typeable, IsString, Pretty, Generic, ToJSON, FromJSON, ToJSONKey, FromJSONKey, Data)

instance Show FnName where
  show = coerce T.unpack

instance Serialize FnName where
  put = coerce putText
  get = coerce getText

$(deriveSafeCopy 0 'base ''FnName)

-- | The name of an NStack type
newtype TyName = TyName Text
  deriving (Eq, Ord, Typeable, Data, IsString, Pretty, Generic, ToJSON, FromJSON, ToJSONKey, FromJSONKey)

instance Show TyName where
  show = coerce T.unpack

instance Serialize TyName where
  put = coerce putText
  get = coerce getText

-- | A fully-qualified function or type name
data Qualified a = Qualified
  { _modName :: ModuleName
  , _unqualName :: a
  }
  deriving (Eq, Ord, Typeable, Generic, Data)

type QFnName = Qualified FnName
type QTyName = Qualified TyName

instance SafeCopy QFnName where
  putCopy (Qualified mod' fn) = contain $ safePut mod' >> safePut fn
  getCopy = contain $ Qualified <$> safeGet <*> safeGet

instance Show a => Show (Qualified a) where
  show (Qualified modName methName) = pprS modName <> "." <> show methName

instance Show a => Pretty (Qualified a) where
  ppr = text . show

instance Serialize a => Serialize (Qualified a)

newtype BaseImage = BaseImage { _baseImage :: T.Text }
  deriving (Eq)

instance Show BaseImage where
  show = coerce (show :: T.Text -> String)

newtype SHA512 = SHA512 { _sha512 :: ByteString } deriving (Eq, Generic)

-- | Takes a textual version of a hash, i.e. that generated by sha512sum, and encode it
mkSHA512 :: Text -> Maybe SHA512
mkSHA512 x = if T.length x == 128 && BS.length hash == 64 && BS.length hashRem == 0 then Just (SHA512 hash) else Nothing
  where (hash, hashRem) = Base16.decode . encodeUtf8 $ x

instance Show SHA512 where
  show = T.unpack . decodeUtf8 . Base16.encode . _sha512

-- data LayerType = BtrfsXz deriving (Eq, Show, Read, Generic)

-- | A image is simply a single btrfs layer, that is applied to other parent module images
-- within the module
data Image = Image {
  -- _layerType :: LayerType, -- mediatype, should be 'btrfs'
  _sha :: SHA512, -- the SHA of the image layer for distribution
  _iUuid :: UUID, -- btrfs uuid
  _size :: Integer -- size in bytes of the compressed form of the layer
} deriving (Show, Eq, Generic)

instance Pretty Image where
  ppr Image{..} = commasep [hashFrag, sizeMb]
    where
      hashFrag = text . take 8 . show $ _sha
      sizeMb = text $ printf "%.1f MB" (fromInteger _size / 1000000 :: Double)

$(deriveSafeCopy 0 'base ''SHA512)
-- $(deriveSafeCopy 0 'base ''LayerType)
$(deriveSafeCopy 0 'base ''Image)

-- instance Serialize LayerType
instance Serialize SHA512
instance Serialize Image

newtype BusName = BusName { _unBusName :: Text } deriving (Eq, Ord, Show, IsString)
data DebugOpt = NoDebug | Debug deriving (Eq, Ord, Show, Generic)

-- monoid instance for DebugOpt is OR
instance Monoid DebugOpt where
  mempty = NoDebug
  NoDebug `mappend` a = a
  Debug   `mappend` _ = Debug

instance Serialize DebugOpt

instance ToJSON DebugOpt where
  toJSON Debug = toJSON True
  toJSON NoDebug = toJSON False


class HasDebugOpt a where
  debugOpt :: Lens' a DebugOpt

unBusName :: Iso' BusName Text
unBusName = iso _unBusName BusName
