using System;
using System.Globalization;
using System.Resources;

namespace Snapboard
{
    internal static class L10n
    {
        private static readonly ResourceManager resources = new ResourceManager(
            "Snapboard.Resources.Strings", typeof(L10n).Assembly);

        // ResourceManager follows the UI culture's parent chain, then neutral English.
        public static string Get(string key) => resources.GetString(key, CultureInfo.CurrentUICulture)
            ?? throw new MissingManifestResourceException(key);

        public static string Format(string key, params object[] arguments) =>
            string.Format(CultureInfo.CurrentUICulture, Get(key), arguments);

        public static string AboutMessage => L10n.Format("windows.about.message",
            typeof(L10n).Assembly.GetName().Version!.ToString(3));
    }
}
