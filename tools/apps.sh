# Sourced by the jank scripts after a() is defined: resolve the apps they drive on the running
# build, so the same runs work on EvoX (Pixel Launcher, Chrome, Google Clock/Photos) and plain
# Lineage (Trebuchet, Jelly, AOSP DeskClock, Glimpse).
#   launcher        home package (quickstep draws overview, so its gfxinfo is the one that counts)
#   browser         package that opens https links; browser_label is its recents card label
#   clock_intent    am start args for the clock app; gallery_intent likewise for photos/gallery
resolve() { a shell "cmd package resolve-activity --brief $*" | tail -1; }
launcher=$(resolve -a android.intent.action.MAIN -c android.intent.category.HOME)
launcher=${launcher%%/*}
browser=$(resolve -a android.intent.action.VIEW -d https://en.wikipedia.org)
browser=${browser%%/*}
case $browser in
	com.android.chrome) browser_label=Chrome ;;
	org.lineageos.jelly) browser_label=Browser ;;
	*) browser_label=$browser ;;
esac
if a shell pm path com.google.android.deskclock | grep -q package:; then
	clock_intent="-n com.google.android.deskclock/com.android.deskclock.DeskClock"
else
	clock_intent="-n com.android.deskclock/.DeskClock"
fi
if a shell pm path com.google.android.apps.photos | grep -q package:; then
	gallery_intent="-n com.google.android.apps.photos/.home.HomeActivity"
else
	gallery_intent="-a android.intent.action.MAIN -c android.intent.category.APP_GALLERY"
fi
echo "apps: launcher=$launcher browser=$browser ($browser_label)" >&2
