// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

namespace System.Caching
{
	public class CacheEntryUpdateArguments
	{
		private String _key;
		private CacheEntryRemovedReason _reason;
		private ObjectCache _source;
		private CacheItem _updatedCacheItem;
		private CacheItemPolicy _updatedCacheItemPolicy;

		public String Key
		{
			get { return _key; }
		}

		public CacheEntryRemovedReason RemovedReason
		{
			get { return _reason; }
		}

		public ObjectCache Source
		{
			get { return _source; }
		}

		public CacheItem UpdatedCacheItem
		{
			get { return _updatedCacheItem; }
			set { _updatedCacheItem = value; }
		}

		public CacheItemPolicy UpdatedCacheItemPolicy
		{
			get { return _updatedCacheItemPolicy; }
			set { _updatedCacheItemPolicy = value; }
		}

		public this(ObjectCache source, CacheEntryRemovedReason reason, String key)
		{
			Runtime.Assert(source != null && key != null);
			_source = source;
			_reason = reason;
			_key = key;
		}
	}
}
