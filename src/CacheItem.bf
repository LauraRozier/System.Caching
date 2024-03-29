// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

namespace System.Caching
{
	public class CacheItem
	{
		public String Key { get; set; }
		public Object Value { get; set; }

		private this() { } // hide default constructor

		public this(String key)
		{
			Key = key;
		}

		public this(String key, Object value) : this(key)
		{
			Value = value;
		}
	}
}
