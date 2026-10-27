using System;
using System.Threading.Tasks;

namespace Snapboard
{
    // Capture entry points run on the UI thread; nested modal message loops can reenter them.
    public sealed class CaptureGate
    {
        private bool active;

        public bool TryRun(Action capture)
        {
            if (active) return false;
            active = true;
            try { capture(); return true; }
            finally { active = false; }
        }

        public async Task<bool> TryRunAsync(Func<Task> capture)
        {
            if (active) return false;
            active = true;
            try { await capture(); return true; }
            finally { active = false; }
        }
    }
}
