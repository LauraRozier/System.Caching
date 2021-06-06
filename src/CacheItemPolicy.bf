// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

using System.Collections;

namespace System.Caching
{
	public class CacheItemPolicy
	{
		private DateTimeOffset _absExpiry;
		private TimeSpan _sldExpiry;
		private List<ChangeMonitor> _changeMonitors ~ DeleteAndNullify!(_);
		private CacheItemPriority _priority;
		private CacheEntryRemovedCallback _removedCallback ~ DeleteAndNullify!(_);
		private CacheEntryUpdateCallback _updateCallback ~ DeleteAndNullify!(_);

		public DateTimeOffset AbsoluteExpiration
		{
			get { return _absExpiry; }
			set { _absExpiry = value; }
		}

		public List<ChangeMonitor> ChangeMonitors
		{
			get
			{
				if (_changeMonitors == null)
					_changeMonitors = new .();

				return _changeMonitors;
			}
		}

		public CacheItemPriority Priority
		{
			get { return _priority; }
			set { _priority = value; }
		}

		public CacheEntryRemovedCallback RemovedCallback
		{
			get { return _removedCallback; }
			set { _removedCallback = value; }
		}

		public TimeSpan SlidingExpiration
		{
			get { return _sldExpiry; }
			set { _sldExpiry = value; }
		}

		public CacheEntryUpdateCallback UpdateCallback
		{
			get { return _updateCallback; }
			set { _updateCallback = value; }
		}

		public this()
		{
			_absExpiry = ObjectCache.InfiniteAbsoluteExpiration;
			_sldExpiry = ObjectCache.NoSlidingExpiration;
			_priority = .Default;
		}
	}
}
