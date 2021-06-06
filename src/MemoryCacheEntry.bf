// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

using System.Collections;
using System.Threading;

namespace System.Caching
{
	sealed class MemoryCacheEntry
	{
		private String _key ~ if (_.IsDynAlloc) delete _;
		private Object _value;
		private DateTime _utcCreated;
		private int _state;
		private DateTime _utcAbsExp;
		private TimeSpan _slidingExp;
		private ExpiresEntryRef _expiresEntryRef;
		private uint8 _expiresBucket;
		private uint8 _usageBucket;
		private UsageEntryRef _usageEntryRef;
		private DateTime _utcLastUpdateUsage;
		private CacheEntryRemovedCallback _callback;
		private MemoryCacheEntry.SeldomUsedFields _fields ~ delete _;
		private readonly Monitor _lock = new .() ~ delete _;

		private class SeldomUsedFields
		{
			public List<ChangeMonitor> _dependencies;
			public Dictionary<MemoryCacheEntryChangeMonitor, MemoryCacheEntryChangeMonitor> _dependents;
			public MemoryCache _cache;
			public (MemoryCacheStore, MemoryCacheEntry) _updateSentinel = default;
		}

		public String Key
		{
			get { return _key; }
		}

		public Object Value
		{
			get { return _value; }
		}

		public bool HasExpiration() =>
			_utcAbsExp < DateTime.MaxValue;

		public DateTime UtcAbsExp
		{
			get { return _utcAbsExp; }
			set { _utcAbsExp = value; }
		}

		public DateTime UtcCreated
		{
			get { return _utcCreated; }
		}

		public ExpiresEntryRef ExpiresEntryReference
		{
			get { return _expiresEntryRef; }
			set { _expiresEntryRef = value; }
		}

		public uint8 ExpiresBucket
		{
			get { return _expiresBucket; }
			set { _expiresBucket = value; }
		}

		public bool InExpires() =>
			!_expiresEntryRef.IsInvalid;

		public TimeSpan SlidingExp
		{
			get { return _slidingExp; }
		}

		public EntryState State
		{
			get { return (EntryState)_state; }
			set { _state = (int)value; }
		}

		public uint8 UsageBucket
		{
			get { return _usageBucket; }
		}

		public UsageEntryRef UsageEntryReference
		{
			get { return _usageEntryRef; }
			set { _usageEntryRef = value; }
		}

		public DateTime UtcLastUpdateUsage
		{
			get { return _utcLastUpdateUsage; }
			set { _utcLastUpdateUsage = value; }
		}

		public this(String key, Object value, DateTimeOffset absExp, TimeSpan slidingExp, CacheItemPriority priority, List<ChangeMonitor> dependencies,
			CacheEntryRemovedCallback removedCallback, MemoryCache cache)
		{
			Runtime.Assert(value != null);

			_utcCreated = DateTime.UtcNow;
			_key = key;
			_value = value;
			_slidingExp = slidingExp;
			_utcAbsExp = _slidingExp > TimeSpan.Zero ? _utcCreated + _slidingExp : absExp.UtcDateTime;
			_expiresEntryRef = ExpiresEntryRef.INVALID;
			_expiresBucket = uint8.MaxValue;
			_usageEntryRef = UsageEntryRef.INVALID;
			_usageBucket = priority == .NotRemovable ? uint8.MaxValue : 0;
			_callback = removedCallback;

			if (dependencies != null)
			{
				_fields = new .();
				_fields._dependencies = dependencies;
				_fields._cache = cache;
			}
		}

		public void AddDependent(MemoryCache cache, MemoryCacheEntryChangeMonitor dependent)
		{
			using (_lock.Enter())
				if (State <= .AddedToCache)
				{
					if (_fields == null)
						_fields = new .();

					if (_fields._cache == null)
						_fields._cache = cache;

					if (_fields._dependents == null)
						_fields._dependents = new .();

					_fields._dependents[dependent] = dependent;
				}
		}

		private void CallCacheEntryRemovedCallback(MemoryCache cache, CacheEntryRemovedReason reason)
		{
			if (_callback == null || reason == .Disposing)
				return;

			_callback(scope .(cache, reason, new .(_key, _value)));
		}

		public void CallNotifyOnChanged()
		{
			if (_fields != null && _fields._dependencies != null)
				for (let changeMonitor in _fields._dependencies)
					changeMonitor.NotifyOnChanged(new => OnDependencyChanged);
		}

		public bool CompareExchangeState(EntryState value, EntryState comparand) =>
			Interlocked.CompareExchange(ref _state, (int)value, (int)comparand) == (int)comparand;

		public void ConfigureUpdateSentinel(MemoryCacheStore sentinelStore, MemoryCacheEntry sentinelEntry)
		{
			using (_lock.Enter())
			{
				if (_fields == null)
					_fields = new .();

				_fields._updateSentinel = (MemoryCacheStore, MemoryCacheEntry)(sentinelStore, sentinelEntry);
			}
		}

		public bool HasUsage() =>
			_usageBucket != uint8.MaxValue;

		public bool InUsage() =>
			!_usageEntryRef.IsInvalid;

		private void OnDependencyChanged(Object state)
		{
			if (State == EntryState.AddedToCache)
				_fields._cache.RemoveEntry(_key, this, .ChangeMonitorChanged);
		}

		public void Release(MemoryCache cache, CacheEntryRemovedReason reason)
		{
			State = EntryState.Closed;
			IEnumerator<MemoryCacheEntryChangeMonitor> keyCollection = null;

			using (_lock.Enter())
				if (_fields != null && _fields._dependents != null && _fields._dependents.Count > 0)
				{
					keyCollection = _fields._dependents.Keys;
					_fields._dependents = null;
				}

			if (keyCollection != null)
				for (let memoryCacheEntryChangeMonitor in keyCollection)
					if (memoryCacheEntryChangeMonitor != null)
						memoryCacheEntryChangeMonitor.OnCacheEntryReleased();

			CallCacheEntryRemovedCallback(cache, reason);
		}

		public void RemoveDependent(MemoryCacheEntryChangeMonitor dependent)
		{
			using (_lock.Enter())
				if (_fields != null && _fields._dependents != null)
					_fields._dependents.Remove(dependent);
		}

		public void UpdateSlidingExp(DateTime utcNow, CacheExpires expires)
		{
			if (_slidingExp > TimeSpan.Zero)
			{
				DateTime dateTime = utcNow + _slidingExp;

				if (dateTime - _utcAbsExp >= CacheExpires.MIN_UPDATE_DELTA || dateTime < _utcAbsExp)
					expires.UtcUpdate(this, dateTime);
			}
		}

		public void UpdateSlidingExpForUpdateSentinel()
		{
			MemoryCacheEntry.SeldomUsedFields fields = _fields;

			if (fields != null)
				if (fields._updateSentinel != default)
					fields._updateSentinel.0.UpdateExpAndUsage(fields._updateSentinel.1);
		}

		public void UpdateUsage(DateTime utcNow, CacheUsage usage)
		{
			if (InUsage() && _utcLastUpdateUsage < utcNow - CacheUsage.CORRELATED_REQUEST_TIMEOUT)
			{
				_utcLastUpdateUsage = utcNow;
				usage.Update(this);

				if (_fields != null && _fields._dependencies != null)
					for (let changeMonitor in _fields._dependencies)
					{
						MemoryCacheEntryChangeMonitor memoryCacheEntryChangeMonitor = (MemoryCacheEntryChangeMonitor)changeMonitor;

						if (memoryCacheEntryChangeMonitor != null)
							for (let memoryCacheEntry in memoryCacheEntryChangeMonitor.Dependencies)
							{
								MemoryCacheStore store = memoryCacheEntry._fields._cache.GetStore(memoryCacheEntry.Key);
								memoryCacheEntry.UpdateUsage(utcNow, store.Usage);
							}
					}
			}
		}
	}
}
