// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

namespace System.Caching
{
	public class CacheEntryRemovedArguments
	{
		private CacheItem _cacheItem ~ DeleteAndNullify!(_); // Needs to be deleted here
		private ObjectCache _source;
		private CacheEntryRemovedReason _reason;

		public CacheItem CacheItem
		{
			get { return _cacheItem; }
		}

		public CacheEntryRemovedReason RemovedReason
		{
			get { return _reason; }
		}

		public ObjectCache Source
		{
			get { return _source; }
		}

		public this(ObjectCache source, CacheEntryRemovedReason reason, CacheItem cacheItem)
		{
			Runtime.Assert(source != null && cacheItem != null);
			_source = source;
			_reason = reason;
			_cacheItem = cacheItem;
		}
	}
}
