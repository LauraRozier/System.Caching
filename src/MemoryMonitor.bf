// This file contains portions of code released by Microsoft under the MIT license as part
// of an open-sourcing initiative in 2014 of the C# core libraries.
// The original source was submitted to https://github.com/Microsoft/referencesource

namespace System.Caching
{
	/// MemoryMonitor is the base class for memory monitors.  The MemoryCache has two types of monitors:  PhysicalMemoryMonitor and CacheMemoryMonitor.  The first monitors
	/// the amount of physical memory used on the machine, and helps determine when we should drop cache entries to avoid paging.  The second monitors the amount of memory used by
	/// the cache itself, and helps determine when we should drop cache entries to avoid exceeding the cache's memory limit.
	abstract class MemoryMonitor
	{
		protected const int TERABYTE_SHIFT = 40;
		protected const int64 TERABYTE = 1L << TERABYTE_SHIFT;

		protected const int GIGABYTE_SHIFT = 30;
		protected const int64 GIGABYTE = 1L << GIGABYTE_SHIFT;

		protected const int MEGABYTE_SHIFT = 20;
		protected const int64 MEGABYTE = 1L << MEGABYTE_SHIFT; // 1048576

		protected const int KILOBYTE_SHIFT = 10;
		protected const int64 KILOBYTE = 1L << KILOBYTE_SHIFT; // 1024

		protected const int HISTORY_COUNT = 6;

		protected int _pressureHigh; // high pressure level
		protected int _pressureLow;  // low pressure level - slow growth here

		protected int _i0;
		protected int[] _pressureHist ~ DeleteAndNullify!(_);
		protected int _pressureTotal;

		private static int64 s_totalPhysical;
		private static int64 s_totalVirtual;

		static this()
		{
			MEMORYSTATUSEX mStatEx = MEMORYSTATUSEX.Init();

			if (NativeMethods.GlobalMemoryStatusEx(&mStatEx) != 0)
			{
				s_totalPhysical = mStatEx.ullTotalPhys;
				s_totalVirtual = mStatEx.ullTotalVirtual;
			}
		}

		public static int64 TotalPhysical
		{
			get { return s_totalPhysical; }
		}

		public static int64 TotalVirtual
		{
			get { return s_totalVirtual; }
		}

		public int PressureLast
		{
			get { return _pressureHist[_i0]; }
		}

		public int PressureHigh
		{
			get { return _pressureHigh; }
		}

		public int PressureLow
		{
			get { return _pressureLow; }
		}

		public bool IsAboveHighPressure() =>
			PressureLast >= PressureHigh;

		protected abstract int GetCurrentPressure();

		public abstract int GetPercentToTrim(DateTime lastTrimTime, int lastTrimPercent);

		protected void InitHistory()
		{
			Runtime.Assert(_pressureHigh > 0 && _pressureLow > 0 && _pressureLow <= _pressureHigh);
			int pressure = GetCurrentPressure();
			_pressureHist = new .[HISTORY_COUNT];

			for (int i = 0; i < HISTORY_COUNT; i++)
			{
				_pressureHist[i] = pressure;
				_pressureTotal += pressure;
			}
		}

		/// Get current pressure and update history
		public void Update()
		{
			int pressure = GetCurrentPressure();
			_i0 = (_i0 + 1) % HISTORY_COUNT;
			_pressureTotal -= _pressureHist[_i0];
			_pressureTotal += pressure;
			_pressureHist[_i0] = pressure;
		}
	}
}
