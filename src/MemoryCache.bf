// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

using System.Collections;
using System.Threading;

namespace System.Caching
{
	public class MemoryCache : ObjectCache, IEnumerable<(String key, ExistingEntry value)>, IDisposable
	{
		private const DefaultCacheCapabilities CAPABILITIES = .InMemoryProvider
			| .CacheEntryChangeMonitors
			| .AbsoluteExpirations
			| .SlidingExpirations
			| .CacheEntryUpdateCallback
			| .CacheEntryRemovedCallback;
		private static readonly TimeSpan OneYear = TimeSpan(365, 0, 0, 0, 0);
		private static Monitor s_initLock = new .() ~ DeleteAndNullify!(_);
		private static MemoryCache s_defaultCache ~ { _.Dispose(); DeleteAndNullify!(_); };
		private static CacheEntryRemovedCallback s_sentinelRemovedCallback = new => SentinelEntry.OnCacheEntryRemovedCallback ~ DeleteAndNullify!(_);
		private MemoryCacheStore[] _storeRefs;
		private int _storeCount;
		private int _disposed;
		private MemoryCacheStatistics _stats;
		private String _name;
		private bool _configLess;
		private bool _useMemoryCacheManager = true;

		private bool IsDisposed
		{
			get { return (_disposed == 1); }
		}
		public bool ConfigLess
		{
			get { return _configLess; }
		}

		private class SentinelEntry
		{
			private String _key;
			private ChangeMonitor _expensiveObjectDependency;
			private CacheEntryUpdateCallback _updateCallback;

			public this(String key, ChangeMonitor expensiveObjectDependency, CacheEntryUpdateCallback callback)
			{
				_key = key;
				_expensiveObjectDependency = expensiveObjectDependency;
				_updateCallback = callback;
			}

			public String Key
			{
				get { return _key; }
			}

			public ChangeMonitor ExpensiveObjectDependency
			{
				get { return _expensiveObjectDependency; }
			}

			public CacheEntryUpdateCallback CacheEntryUpdateCallback
			{
				get { return _updateCallback; }
			}

			private static bool IsPolicyValid(CacheItemPolicy policy)
			{
				if (policy == null)
					return false;

				// see if any change monitors have changed
				bool hasChanged = false;
				List<ChangeMonitor> changeMonitors = policy.ChangeMonitors;

				if (changeMonitors != null)
					for (let monitor in changeMonitors)
						if (monitor != null && monitor.HasChanged)
						{
							hasChanged = true;
							break;
						}

				// if the monitors haven't changed yet and we have an update callback then the policy is valid
				if (!hasChanged && policy.UpdateCallback != null)
					return true;

				// if the monitors have changed we need to dispose them
				if (hasChanged)
					for (var monitor in changeMonitors)
						if (monitor != null)
						{
							monitor.Dispose();
							DeleteAndNullify!(monitor);
						}

				return false;
			}

			public static void OnCacheEntryRemovedCallback(CacheEntryRemovedArguments arguments)
			{
				MemoryCache cache = (MemoryCache)arguments.Source;
				SentinelEntry entry = (SentinelEntry)arguments.CacheItem.Value;
				CacheEntryRemovedReason reason = arguments.RemovedReason;

				switch (reason)
				{
				case .Expired:
					break;
				case .ChangeMonitorChanged:
					if (entry.ExpensiveObjectDependency.HasChanged)
						// If the expensiveObject has been removed explicitly by Cache.Remove, return from the
						// SentinelEntry removed callback thus effectively removing the SentinelEntry from the cache.
						return;

					break;
				case .Evicted:
					Runtime.FatalError("Fatal error: Reason should never be CacheEntryRemovedReason.Evicted since the entry was inserted as NotRemovable.");
				default:
						// do nothing if reason is Removed or CacheSpecificEviction
					return;
				}

				// invoke update callback
				CacheEntryUpdateArguments args = scope .(cache, reason, entry.Key);
				entry.CacheEntryUpdateCallback(args);
				Object expensiveObject = (args.UpdatedCacheItem != null) ? args.UpdatedCacheItem.Value : null;
				CacheItemPolicy policy = args.UpdatedCacheItemPolicy;

				// Only update the "expensive" Object if the user returns a new Object, a policy with update callback, and the change monitors haven't changed.
				// (Inserting with change monitors that have already changed will cause recursion.)
				if (expensiveObject != null && IsPolicyValid(policy)) {
					cache.Set(entry.Key, expensiveObject, policy);
				} else {
					cache.Remove(entry.Key);
				}
			}
		}

		public MemoryCacheStore GetStore(String cacheKey)
		{
			int hashCode = cacheKey.GetHashCode();

			if (hashCode < 0)
				hashCode = (hashCode == Int32.MinValue) ? 0 : -hashCode;

			return _storeRefs[hashCode % _storeCount];
		}

		public MemoryCacheStore[] AllSRefTargets
		{
			get
			{
				MemoryCacheStore[] allStores = new .[_storeCount];

				for (int i = 0; i < _storeCount; i++)
					allStores[i] = _storeRefs[i];

				return allStores;
			}
		}

		private void ValidatePolicy(CacheItemPolicy policy)
		{
			Runtime.Assert(policy.AbsoluteExpiration == .InfiniteAbsoluteExpiration || policy.SlidingExpiration == .NoSlidingExpiration);
			Runtime.Assert(policy.SlidingExpiration > .NoSlidingExpiration || OneYear >= policy.SlidingExpiration);
			Runtime.Assert(policy.RemovedCallback == null || policy.UpdateCallback == null);
			Runtime.Assert(policy.Priority >= .Default && policy.Priority <= .NotRemovable);
		}

		/// Amount of memory that can be used before the cache begins to forcibly remove items.
		public int64 CacheMemoryLimit
		{
			get { return _stats.CacheMemoryLimit; }
		}

		public static MemoryCache Default
		{
			get
			{
				using (s_initLock.Enter())
					if (s_defaultCache == null)
						s_defaultCache = new .();

				return s_defaultCache;
			}
		}

		public override DefaultCacheCapabilities DefaultCacheCapabilities
		{
			get { return CAPABILITIES; }
		}

		public override String Name
		{
			get { return _name; }
		}

		public bool UseMemoryCacheManager
		{
			get { return _useMemoryCacheManager; }
		}

		/// Percentage of physical memory that can be used before the cache begins to forcibly remove items.
		public int64 PhysicalMemoryLimit
		{
			get { return _stats.PhysicalMemoryLimit; }
		}

		/// The maximum interval of time after which the cache will update its memory statistics.
		public TimeSpan PollingInterval
		{
			get { return _stats.PollingInterval; }
		}

		/// Only used for Default MemoryCache
		private this()
		{
			_name = "Default";
			Init();
		}

		public this(String name)
		{
			Runtime.Assert(!String.IsNullOrWhiteSpace(name) && !name.Equals("Default"));
			_name = name;
			Init();
		}

		public this(String name, bool ignoreConfigSection)
		{
			Runtime.Assert(!String.IsNullOrWhiteSpace(name) && !name.Equals("Default"));
			_name = name;
			_configLess = ignoreConfigSection;
			Init();
		}

		private void Init()
		{
			_storeCount = Platform.ProcessorCount;
			_storeRefs = new .[_storeCount];
			_useMemoryCacheManager = true;

			for (int i = 0; i < _storeCount; i++)
				_storeRefs[i] = new .(this);

			_stats = new .(this);
		}

		private ExistingEntry AddOrGetExistingInternal(String key, Object value, CacheItemPolicy policy, bool deleteValueIfExists)
		{
			Runtime.Assert(key != null);
			DateTimeOffset absExp = ObjectCache.InfiniteAbsoluteExpiration;
			TimeSpan slidingExp = ObjectCache.NoSlidingExpiration;
			CacheItemPriority priority = .Default;
			List<ChangeMonitor> changeMonitors = null;
			CacheEntryRemovedCallback removedCallback = null;

			if (policy != null)
			{
				ValidatePolicy(policy);
				Runtime.Assert(policy.UpdateCallback == null);

				absExp = policy.AbsoluteExpiration;
				slidingExp = policy.SlidingExpiration;
				priority = policy.Priority;
				changeMonitors = policy.ChangeMonitors;
				removedCallback = policy.RemovedCallback;
			}

			if (IsDisposed)
			{
				if (changeMonitors != null)
					for (var monitor in changeMonitors)
						if (monitor != null)
						{
							monitor.Dispose();
							DeleteAndNullify!(monitor);
						}

				return default;
			}

			MemoryCacheEntry entry = GetStore(key).AddOrGetExisting(
				key, new .(key, value, absExp, slidingExp, priority, changeMonitors, removedCallback, this), deleteValueIfExists
			);
			return entry != null ? .(entry.State, entry.Value) : default;
		}

		public override CacheEntryChangeMonitor CreateCacheEntryChangeMonitor(IEnumerator<String> keys)
		{
			Runtime.Assert(keys != null);
			List<String> keysClone = new .(keys);
			Runtime.Assert(keysClone.Count > 0);

			for (String key in keysClone)
				Runtime.Assert(key != null);

			return new MemoryCacheEntryChangeMonitor(keysClone, this);
		}

		public void Dispose()
		{
			if (Interlocked.Exchange(ref _disposed, 1) == 0)
			{
				// stats must be disposed prior to disposing the stores.
				if (_stats != null)
				{
					_stats.Dispose();
					DeleteAndNullify!(_stats);
				}

				if (_storeRefs != null)
				{
					for (var storeRef in _storeRefs)
						if (storeRef != null)
						{
							storeRef.Dispose();
							DeleteAndNullify!(storeRef);
						}

					DeleteAndNullify!(_storeRefs);
				}

				if (_name != null && _name.IsDynAlloc)
					DeleteAndNullify!(_name);
			}
		}

		private ExistingEntry GetInternal(String key)
		{
			Runtime.Assert(key != null);
			MemoryCacheEntry entry = GetEntry(key);
			return (entry != null) ? .(entry.State, entry.Value) : default;
		}

		public MemoryCacheEntry GetEntry(String key)
		{
			if (IsDisposed)
				return null;

			return GetStore(key).Get(key);
		}

		public override IEnumerator<(String key, ExistingEntry value)> GetEnumerator()
		{
			Dictionary<String, ExistingEntry> h = new .();

			if (!IsDisposed)
				for (var storeRef in _storeRefs)
					storeRef.CopyTo(ref h);

			return new box h.GetEnumerator();
		}

		public MemoryCacheEntry RemoveEntry(String key, MemoryCacheEntry entry, CacheEntryRemovedReason reason) =>
			GetStore(key).Remove(key, entry, reason);

		public int64 Trim(int percent)
		{
			var percent;

			if (percent > 100)
				percent = 100;

			int64 trimmed = 0;

			if (_disposed == 0)
				for (let storeRef in _storeRefs)
					trimmed += storeRef.TrimInternal(percent);

			return trimmed;
		}

		/// Default indexer property
		public override ExistingEntry this[String key]
		{
			get { return GetInternal(key); }
			set { Set(key, value, .InfiniteAbsoluteExpiration); }
		}

		/// Existence check for a single item
		public override bool Contains(String key) =>
			GetInternal(key) != default;

		/// Breaking bug in System.RuntimeCaching.MemoryCache.AddOrGetExisting (CacheItem, CacheItemPolicy)
		public override bool Add(CacheItem item, CacheItemPolicy policy, bool deleteValueIfExists)
		{
			CacheItem existingEntry = AddOrGetExisting(item, policy, deleteValueIfExists);
			return (existingEntry == null || existingEntry.Value == null);
		}

		public override ExistingEntry AddOrGetExisting(String key, Object value, DateTimeOffset absoluteExpiration, bool deleteValueIfExists)
		{
			CacheItemPolicy policy = new .();
			policy.AbsoluteExpiration = absoluteExpiration;
			return AddOrGetExistingInternal(key, value, policy, deleteValueIfExists);
		}

		public override CacheItem AddOrGetExisting(CacheItem item, CacheItemPolicy policy, bool deleteValueIfExists)
		{
			Runtime.Assert(item != null);
			return new .(item.Key, AddOrGetExistingInternal(item.Key, item.Value, policy, deleteValueIfExists));
		}

		public override ExistingEntry AddOrGetExisting(String key, Object value, CacheItemPolicy policy, bool deleteValueIfExists) =>
			AddOrGetExistingInternal(key, value, policy, deleteValueIfExists);

		public override ExistingEntry Get(String key) =>
			GetInternal(key);

		public override CacheItem GetCacheItem(String key)
		{
			ExistingEntry value = GetInternal(key);
			return (value != default) ? new .(key, value.Value) : null;
		}

		public override void Set(String key, Object value, DateTimeOffset absoluteExpiration)
		{
			CacheItemPolicy policy = new .();
			policy.AbsoluteExpiration = absoluteExpiration;
			Set(key, value, policy);
		}

		public override void Set(CacheItem item, CacheItemPolicy policy)
		{
			Runtime.Assert(item != null);
			Set(item.Key, item.Value, policy);
		}

		public override void Set(String key, Object value, CacheItemPolicy policy)
		{
			Runtime.Assert(key != null);
			DateTimeOffset absExp = ObjectCache.InfiniteAbsoluteExpiration;
			TimeSpan slidingExp = ObjectCache.NoSlidingExpiration;
			CacheItemPriority priority = .Default;
			List<ChangeMonitor> changeMonitors = null;
			CacheEntryRemovedCallback removedCallback = null;

			if (policy != null)
			{
				ValidatePolicy(policy);

				if (policy.UpdateCallback != null)
				{
					Set(key, value, policy.ChangeMonitors, policy.AbsoluteExpiration, policy.SlidingExpiration, policy.UpdateCallback);
					return;
				}

				absExp = policy.AbsoluteExpiration;
				slidingExp = policy.SlidingExpiration;
				priority = policy.Priority;
				changeMonitors = policy.ChangeMonitors;
				removedCallback = policy.RemovedCallback;
			}

			if (IsDisposed)
			{
				if (changeMonitors != null)
				{
					for (var monitor in changeMonitors)
						if (monitor != null)
						{
							monitor.Dispose();
							DeleteAndNullify!(monitor);
						}

					changeMonitors.Clear();
				}

				return;
			}

			GetStore(key).Set(key, new .(key, value, absExp, slidingExp, priority, changeMonitors, removedCallback, this));
		}

		// Add a an event that fires *before* an item is evicted from the Cache
		public void Set(String key, Object value, List<ChangeMonitor> changeMonitors, DateTimeOffset absoluteExpiration, TimeSpan slidingExpiration, CacheEntryUpdateCallback onUpdateCallback)
		{
			var changeMonitors;
			Runtime.Assert(key != null
				&& (changeMonitors != null && absoluteExpiration != ObjectCache.InfiniteAbsoluteExpiration && slidingExpiration != ObjectCache.NoSlidingExpiration)
				&& onUpdateCallback != null);

			if (IsDisposed)
			{
				if (changeMonitors != null)
					for (var monitor in changeMonitors)
						if (monitor != null)
						{
							monitor.Dispose();
							DeleteAndNullify!(monitor);
						}

				return;
			}

			// Insert updatable cache entry
			MemoryCacheEntry cacheEntry = new .(key, value, ObjectCache.InfiniteAbsoluteExpiration, ObjectCache.NoSlidingExpiration, .NotRemovable, null, null, this);
			GetStore(key).Set(key, cacheEntry);

			// Ensure the sentinel depends on its updatable entry
			String[?] cacheKeys = .(key);
			ChangeMonitor expensiveObjectDep = CreateCacheEntryChangeMonitor(cacheKeys.GetEnumerator());

			if (changeMonitors == null)
				changeMonitors = new .();

			changeMonitors.Add(expensiveObjectDep);

			// Insert sentinel entry for the updatable cache entry
			String sentinelCacheKey = new $"OnUpdateSentinel{key}";
			MemoryCacheStore sentinelStore = GetStore(sentinelCacheKey);
			MemoryCacheEntry sentinelCacheEntry = new .(sentinelCacheKey, new SentinelEntry(key, expensiveObjectDep, onUpdateCallback), absoluteExpiration,
				slidingExpiration, .NotRemovable, changeMonitors, s_sentinelRemovedCallback, this);
			sentinelStore.Set(sentinelCacheKey, sentinelCacheEntry);
			cacheEntry.ConfigureUpdateSentinel(sentinelStore, sentinelCacheEntry);
		}

		public override Object Remove(String key) =>
			Remove(key, .Removed);

		public Object Remove(String key, CacheEntryRemovedReason reason)
		{
			Runtime.Assert(key != null);

			if (IsDisposed)
				return null;

			MemoryCacheEntry entry = RemoveEntry(key, null, reason);
			return (entry != null) ? entry.Value : null;
		}

		public override int64 GetCount()
		{
			int64 count = 0;

			if (!IsDisposed)
				for (var storeRef in _storeRefs)
					count += storeRef.Count;

			return count;
		}

		public int64 GetLastSize() =>
			_stats.GetLastSize();

		public override Dictionary<String, Object> GetValues(List<String> keys)
		{
			Runtime.Assert(keys != null);
			Dictionary<String, Object> values = new .();

			if (!IsDisposed)
				for (let key in keys)
				{
					Runtime.Assert(key != null);
					Object value = GetInternal(key);

					if (value != null)
						values[key] = value;
				}

			// We can also just return an empty list :) no need for null
			return values;
		}
	}
}
