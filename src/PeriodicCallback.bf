using System;
using System.Diagnostics;
using System.Threading;

namespace System.Caching
{
	public sealed class PeriodicCallback : IDisposable
	{
		public const uint32 MAX_SUPPORTED_TIMEOUT = (uint32)0xfffffffeU;

		private bool _disposed = false;
		private int _interval;
		private PeriodicCallbackDelegate _callback;
		private Thread _thread = null;
		private WaitEvent _cancelEvent = new .(false);

		private this() { } // Hide parameterless .ctor

		/// Creates a new instance of the PeriodicCallback with a default timeout of 1 second, the delegate is owned by this object and will be deleted by it
		public this(PeriodicCallbackDelegate callback) : this(callback, TimeSpan(0, 0, 1)) { }

		/// Creates a new instance of the PeriodicCallback, the delegate is owned by this object and will be deleted by it
		public this(PeriodicCallbackDelegate callback, int interval) : this(callback, (int64)interval) { }

		/// Creates a new instance of the PeriodicCallback, the delegate is owned by this object and will be deleted by it
		public this(PeriodicCallbackDelegate callback, int64 interval)
		{
			Runtime.Assert(callback != null && interval >= -1 && interval <= MAX_SUPPORTED_TIMEOUT);

			_callback = callback;
			_interval = (int)interval;
			_thread = new .(new => ThreadExecute);
			_thread.Start(false);
		}

		/// Creates a new instance of the PeriodicCallback, the delegate is owned by this object and will be deleted by it
		public this(PeriodicCallbackDelegate callback, TimeSpan interval) : this(callback, (int64)interval.TotalMilliseconds) { }

		/// Creates a new instance of the PeriodicCallback, the delegate is owned by this object and will be deleted by it
		public this(PeriodicCallbackDelegate callback, uint32 interval) : this(callback, (int64)interval) { }

		public ~this()
		{
			if (!_disposed)
				Dispose();
		}

		public void Dispose()
		{
			_cancelEvent.Set(true);
			_thread.Join();
			DeleteAndNullify!(_thread);
			DeleteAndNullify!(_callback);
			DeleteAndNullify!(_cancelEvent);
			_disposed = true;
		}

		/// Update the interval with which the callback is called, this resets the internal thread so you will
		/// potentially miss an interval
		public void UpdateInterval(int interval) =>
			UpdateInterval((int64)interval);

		/// Update the interval with which the callback is called, this resets the internal thread so you will
		/// potentially miss an interval
		public void UpdateInterval(int64 interval)
		{
			Runtime.Assert(interval >= -1 && interval <= MAX_SUPPORTED_TIMEOUT);

			_cancelEvent.Set(true);
			_interval = (int)interval;
			_thread.Join();
			_cancelEvent.Reset();
			_thread.Start(false);
		}

		/// Update the interval with which the callback is called, this resets the internal thread so you will
		/// potentially miss an interval
		public void UpdateInterval(TimeSpan interval) =>
			UpdateInterval((int64)interval.TotalMilliseconds);

		/// Update the interval with which the callback is called, this resets the internal thread so you will
		/// potentially miss an interval
		public void UpdateInterval(uint32 interval) =>
			UpdateInterval((int64)interval);

		/// Thread execute procedure
		private void ThreadExecute()
		{
			Stopwatch sw = scope .();
			int lastProcTime = 0;
			int adjustedInterval;

			while (_thread.ThreadState == .Running)
			{
				// Remove the time it took to process the callback from the set interval
				adjustedInterval = _interval - lastProcTime;

				if (adjustedInterval < 0)
					adjustedInterval = 0;

				if (_cancelEvent.WaitFor(adjustedInterval))
					return; // Terminate thread when _cancelEvent is set

				sw.Restart();
				_callback(this);
				sw.Stop();
				lastProcTime = (int)sw.ElapsedMilliseconds;
			}
		}
	}
}
