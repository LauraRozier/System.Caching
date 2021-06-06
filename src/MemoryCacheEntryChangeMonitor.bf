// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

using System.Collections;
using System.Globalization;

namespace System.Caching
{
	sealed class MemoryCacheEntryChangeMonitor : CacheEntryChangeMonitor
	{
		private static readonly DateTime s_DATETIME_MINVALUE_UTC = DateTime(0L, DateTimeKind.Utc);
		private const int MAX_CHAR_COUNT_OF_LONG_CONVERTED_TO_HEXADECIMAL_STRING = 16;
		private List<String> _keys;
		private String _uniqueId;
		private DateTimeOffset _lastModified;
		private List<MemoryCacheEntry> _dependencies;

		public override List<String> CacheKeys
		{
			get { return new .(_keys.GetEnumerator()); }
		}

		public override String UniqueId
		{
			get { return _uniqueId; }
		}

		public override DateTimeOffset LastModified
		{
			get { return _lastModified; }
		}

		public List<MemoryCacheEntry> Dependencies
		{
			get { return _dependencies; }
		}

		private this() { }

		public this(List<String> keys, MemoryCache cache)
		{
			_keys = keys;
			InitDisposableMembers(cache);
		}

		private void InitDisposableMembers(MemoryCache cache)
		{
			bool hasChanged = false;
			_dependencies = new .(_keys.Count);
			String uniqueId = scope .();

			if (_keys.Count == 1)
			{
				String text = _keys[0];
				DateTime dateTime = s_DATETIME_MINVALUE_UTC;
				StartMonitoring(cache, cache.GetEntry(text), ref hasChanged, ref dateTime);

				uniqueId.Append(text);
				dateTime.Ticks.ToString(uniqueId, "X", CultureInfo.InvariantCulture);
				_lastModified = dateTime;
			}
			else
			{
				int capacity = 0;

				for (String key in _keys)
					capacity += key.Length + 16;

				String stringBuilder = scope .(capacity);

				for (let key in _keys)
				{
					DateTime utcCreated = s_DATETIME_MINVALUE_UTC;
					StartMonitoring(cache, cache.GetEntry(key), ref hasChanged, ref utcCreated);
					stringBuilder.Append(key);
					utcCreated.Ticks.ToString(stringBuilder, "X", CultureInfo.InvariantCulture);

					if (utcCreated > _lastModified)
						_lastModified = utcCreated;
				}

				uniqueId.Set(stringBuilder);
			}

			_uniqueId = uniqueId;

			if (hasChanged)
				base.OnChanged(null);

			base.InitializationComplete();
		}

		private void StartMonitoring(MemoryCache cache, MemoryCacheEntry entry, ref bool hasChanged, ref DateTime utcCreated)
		{
			if (entry != null)
			{
				entry.AddDependent(cache, this);
				_dependencies.Add(entry);

				if (entry.State != .AddedToCache)
					hasChanged = true;

				utcCreated = entry.UtcCreated;
				return;
			}

			hasChanged = true;
		}

		protected override void Dispose(bool disposing)
		{
			if (disposing && _dependencies != null)
				for (let memoryCacheEntry in _dependencies)
					if (memoryCacheEntry != null)
						memoryCacheEntry.RemoveDependent(this);
		}

		public void OnCacheEntryReleased() =>
			OnChanged(null);
	}
}
