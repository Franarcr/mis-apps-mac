package local.fran.iniciotv;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.content.pm.ResolveInfo;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.drawable.BitmapDrawable;
import android.graphics.drawable.ColorDrawable;
import android.graphics.drawable.TransitionDrawable;
import android.graphics.Outline;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewOutlineProvider;
import android.widget.FrameLayout;
import android.widget.HorizontalScrollView;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.TextClock;
import android.widget.TextView;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Pantalla de inicio minimalista al estilo Apple TV: hora arriba y tres filas.
 * Favoritas · Más apps · TV (TV en vivo, entradas y configuración).
 */
public class HomeActivity extends Activity {

    /** Primera fila, en este orden (las que estén instaladas). */
    private static final List<String> FAVORITES = Arrays.asList(
            "com.netflix.ninja",                        // Netflix
            "com.google.android.youtube.tv",            // YouTube
            "com.disney.disneyplus",                    // Disney+
            "com.wbd.stream", "com.hbo.hbomax",         // Max
            "com.amazon.amazonvideo.livingroom",        // Prime Video
            "com.apple.atve.androidtv.appletv");        // Apple TV

    /** Apps que no se muestran: las de Google que no se usan y las del sistema que van en la fila de TV. */
    private static final Set<String> HIDDEN = new HashSet<>(Arrays.asList(
            "com.android.vending",                      // Google Play Store
            "com.google.android.play.games",            // Google Play Juegos
            "com.google.android.videos",                // Google TV (películas)
            "com.mediatek.wwtv.tvcenter",               // TV en vivo (va en la fila de TV)
            "com.android.tv.settings",                  // Configuración (va en la fila de TV)
            "com.mediatek.androidbox",
            "com.mediatek.wwtv.mediaplayer",            // MMP
            "org.videolan.vlc",                         // VLC
            "com.univision.prendetv",                   // ViX
            "com.FDGEntertainment.redball4.gp",         // Red Ball 4
            "com.radio.fmradio",                        // Radio FM
            "com.mubi",                                 // MUBI
            "com.iqiyi.i18n.tv",                        // iQIYI
            "com.tcl.browser",                          // BrowseHere
            "com.Tv.Receiver.phonetotv.casting.screenmirroring.Recievertv")); // Screen mirroring

    private static final String LIVE_TV = "com.mediatek.wwtv.tvcenter";

    private LinearLayout rows;
    /** Fondo de pantalla completa: la imagen de la app seleccionada, muy difuminada (como en Apple TV). */
    private ImageView backdrop;
    private Drawable currentBackdrop;
    private final BroadcastReceiver packagesChanged = new BroadcastReceiver() {
        @Override public void onReceive(Context c, Intent i) { loadApps(); }
    };

    @Override
    protected void onCreate(Bundle state) {
        super.onCreate(state);
        FrameLayout root = new FrameLayout(this);
        backdrop = new ImageView(this);
        backdrop.setScaleType(ImageView.ScaleType.FIT_XY);
        currentBackdrop = new ColorDrawable(0xFF0E141B);
        backdrop.setImageDrawable(currentBackdrop);
        root.addView(backdrop, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        View shade = new View(this);
        shade.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM, new int[]{0x55000000, 0x99000000, 0xF0050709}));
        root.addView(shade, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        // Hora y fecha, arriba a la derecha.
        LinearLayout clock = new LinearLayout(this);
        clock.setOrientation(LinearLayout.VERTICAL);
        clock.setGravity(Gravity.END);
        TextClock time = new TextClock(this);
        time.setFormat24Hour("H:mm");
        time.setFormat12Hour("h:mm");
        time.setTextColor(Color.WHITE);
        time.setTextSize(TypedValue.COMPLEX_UNIT_SP, 26);
        time.setTypeface(Typeface.create("sans-serif-medium", Typeface.NORMAL));
        TextClock date = new TextClock(this);
        date.setFormat24Hour("EEEE d 'de' MMMM");
        date.setFormat12Hour("EEEE d 'de' MMMM");
        date.setTextColor(0x99FFFFFF);
        date.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14);
        clock.addView(time);
        clock.addView(date);
        FrameLayout.LayoutParams clp = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.TOP | Gravity.END);
        clp.setMargins(0, dp(24), dp(56), 0);
        root.addView(clock, clp);

        // Las tres filas, abajo.
        rows = new LinearLayout(this);
        rows.setOrientation(LinearLayout.VERTICAL);
        rows.setClipChildren(false);
        FrameLayout.LayoutParams rlp = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.BOTTOM);
        rlp.bottomMargin = dp(28);
        root.addView(rows, rlp);

        setContentView(root);
        IntentFilter f = new IntentFilter();
        f.addAction(Intent.ACTION_PACKAGE_ADDED);
        f.addAction(Intent.ACTION_PACKAGE_REMOVED);
        f.addAction(Intent.ACTION_PACKAGE_CHANGED);
        f.addDataScheme("package");
        registerReceiver(packagesChanged, f);
        loadApps();
    }

    @Override
    protected void onResume() {
        super.onResume();
        getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY);
    }

    @Override
    protected void onNewIntent(Intent intent) {
        super.onNewIntent(intent);
        focusFirst();
    }

    @Override
    protected void onDestroy() {
        unregisterReceiver(packagesChanged);
        super.onDestroy();
    }

    /** Siendo la pantalla de inicio, «atrás» no hace nada. */
    @Override
    public boolean onKeyDown(int keyCode, KeyEvent event) {
        if (keyCode == KeyEvent.KEYCODE_BACK) return true;
        return super.onKeyDown(keyCode, event);
    }

    private static class App {
        String pkg, name;
        Drawable banner, icon;
        Intent launch;
    }

    private void loadApps() {
        PackageManager pm = getPackageManager();
        Intent q = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER);
        List<App> favorites = new ArrayList<>(), others = new ArrayList<>();
        Set<String> seen = new HashSet<>();
        for (ResolveInfo ri : pm.queryIntentActivities(q, 0)) {
            ActivityInfo ai = ri.activityInfo;
            if (!seen.add(ai.packageName) || ai.packageName.equals(getPackageName()) || HIDDEN.contains(ai.packageName)) continue;
            App a = new App();
            a.pkg = ai.packageName;
            a.name = String.valueOf(ri.loadLabel(pm));
            a.banner = ai.loadBanner(pm);
            if (a.banner == null) a.banner = ai.applicationInfo.loadBanner(pm);
            if (a.banner == null) a.icon = ri.loadIcon(pm);
            a.launch = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
                    .setClassName(ai.packageName, ai.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            (FAVORITES.contains(a.pkg) ? favorites : others).add(a);
        }
        favorites.sort((x, y) -> Integer.compare(FAVORITES.indexOf(x.pkg), FAVORITES.indexOf(y.pkg)));
        others.sort((x, y) -> x.name.toLowerCase(Locale.ROOT).compareTo(y.name.toLowerCase(Locale.ROOT)));

        rows.removeAllViews();
        // Cuadrícula fija de 5 columnas: todas las apps a la vista, sin desplazarse de lado.
        List<App> all = new ArrayList<>(favorites);
        all.addAll(others);
        LinearLayout row = null;
        for (int i = 0; i < all.size(); i++) {
            if (i % COLUMNS == 0) row = newRow(dp(4));
            App a = all.get(i);
            row.addView(tile(a.name, a.banner, a.icon, a.launch));
        }

        // Abajo, en botones pequeños: TV en vivo, selector de entradas y configuración.
        LinearLayout tv = newRow(dp(18));
        Intent live = pm.getLeanbackLaunchIntentForPackage(LIVE_TV);
        if (live != null) tv.addView(pill("TV en vivo", R.drawable.ic_tv, live.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)));
        Intent inputs = new Intent("com.android.tv.action.VIEW_INPUTS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        if (inputs.resolveActivity(pm) != null) tv.addView(pill("Entradas", R.drawable.ic_input, inputs));
        Intent settings = new Intent(android.provider.Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        tv.addView(pill("Configuración", R.drawable.ic_gear, settings));
        focusFirst();
    }

    private static final int COLUMNS = 5;

    private LinearLayout newRow(int top) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setClipChildren(false);
        row.setClipToPadding(false);
        row.setPadding(dp(56), top, dp(56), 0);
        rows.addView(row);
        return row;
    }

    /** Botón pequeño con ícono y texto, para la fila de TV. */
    private View pill(String name, int iconRes, Intent launch) {
        LinearLayout p = new LinearLayout(this);
        p.setOrientation(LinearLayout.HORIZONTAL);
        p.setGravity(Gravity.CENTER);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(0x33FFFFFF);
        bg.setCornerRadius(dp(20));
        p.setBackground(bg);
        ImageView img = new ImageView(this);
        Drawable icon = getDrawable(iconRes).mutate();
        img.setImageDrawable(icon);
        p.addView(img, new LinearLayout.LayoutParams(dp(18), dp(18)));
        TextView label = new TextView(this);
        label.setText(name);
        label.setTextColor(Color.WHITE);
        label.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        label.setPadding(dp(8), 0, 0, 0);
        p.addView(label);
        p.setFocusable(true);
        p.setOnClickListener(v -> {
            try { startActivity(launch); } catch (Exception ignored) { }
        });
        p.setOnFocusChangeListener((v, has) -> {
            bg.setColor(has ? 0xFFFFFFFF : 0x33FFFFFF);
            label.setTextColor(has ? 0xFF111111 : Color.WHITE);
            icon.setTint(has ? 0xFF111111 : Color.WHITE);
            v.animate().scaleX(has ? 1.08f : 1f).scaleY(has ? 1.08f : 1f).setDuration(150).start();
            if (has) showBackdrop(darkBackdrop);
        });
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(150), dp(38));
        lp.setMargins(0, 0, dp(20), 0);
        p.setLayoutParams(lp);
        return p;
    }

    private final Drawable darkBackdrop = new ColorDrawable(0xFF0E141B);

    /** Al volver al inicio, la selección empieza en la primera app. */
    private void focusFirst() {
        rows.post(() -> {
            if (rows.getChildCount() == 0) return;
            ViewGroup first = (ViewGroup) rows.getChildAt(0);
            if (first.getChildCount() == 0) return;
            View cell = first.getChildAt(0);
            (cell instanceof ViewGroup && ((ViewGroup) cell).getChildCount() > 0 && !cell.isFocusable() ? ((ViewGroup) cell).getChildAt(0) : cell).requestFocus();
        });
    }

    private View tile(String name, Drawable banner, Drawable icon, Intent launch) {
        FrameLayout t = new FrameLayout(this);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(0xFF1E2630);
        bg.setCornerRadius(dp(12));
        t.setBackground(bg);
        t.setOutlineProvider(new ViewOutlineProvider() {
            @Override public void getOutline(View v, Outline o) { o.setRoundRect(0, 0, v.getWidth(), v.getHeight(), dp(12)); }
        });
        t.setClipToOutline(true);
        if (banner != null) {
            ImageView img = new ImageView(this);
            img.setImageDrawable(banner);
            img.setScaleType(ImageView.ScaleType.CENTER_CROP);
            t.addView(img, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        } else {
            // Sin banner: ícono y nombre.
            LinearLayout box = new LinearLayout(this);
            box.setOrientation(LinearLayout.VERTICAL);
            box.setGravity(Gravity.CENTER);
            ImageView img = new ImageView(this);
            img.setImageDrawable(icon);
            img.setScaleType(ImageView.ScaleType.FIT_CENTER);
            box.addView(img, new LinearLayout.LayoutParams(dp(34), dp(34)));
            TextView label = new TextView(this);
            label.setText(name);
            label.setTextColor(Color.WHITE);
            label.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12);
            label.setSingleLine(true);
            label.setGravity(Gravity.CENTER_HORIZONTAL);
            label.setPadding(dp(6), dp(6), dp(6), 0);
            box.addView(label);
            t.addView(box, new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));
        }
        t.setFocusable(true);
        t.setContentDescription(name);
        t.setOnClickListener(v -> {
            try { startActivity(launch); } catch (Exception ignored) { }
        });
        // Nombre debajo, solo en la app seleccionada.
        TextView name_ = new TextView(this);
        name_.setText(name);
        name_.setTextColor(Color.WHITE);
        name_.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        name_.setGravity(Gravity.CENTER);
        name_.setSingleLine(true);
        name_.setAlpha(0f);
        Drawable blurred = blurred(banner);
        t.setOnFocusChangeListener((v, has) -> {
            float s = has ? 1.15f : 1f;
            v.animate().scaleX(s).scaleY(s).translationZ(has ? dp(20) : 0).setDuration(180).start();
            name_.animate().alpha(has ? 1f : 0f).translationY(has ? dp(8) : 0).setDuration(180).start();
            if (has) showBackdrop(blurred);
        });
        LinearLayout cell = new LinearLayout(this);
        cell.setOrientation(LinearLayout.VERTICAL);
        cell.setClipChildren(false);
        cell.addView(t, new LinearLayout.LayoutParams(dp(150), dp(84)));
        cell.addView(name_, new LinearLayout.LayoutParams(dp(150), dp(22)));
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(ViewGroup.LayoutParams.WRAP_CONTENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.setMargins(0, 0, dp(20), 0);
        cell.setLayoutParams(lp);
        return cell;
    }

    /** La imagen reducida a unos pocos píxeles y vuelta a agrandar: queda un difuminado suave de sus colores. */
    private Drawable blurred(Drawable d) {
        if (d == null) return new ColorDrawable(0xFF0E141B);
        Bitmap small = Bitmap.createBitmap(32, 18, Bitmap.Config.ARGB_8888);
        Canvas c = new Canvas(small);
        d = d.getConstantState() != null ? d.getConstantState().newDrawable().mutate() : d;
        d.setBounds(0, 0, 32, 18);
        d.draw(c);
        Bitmap big = Bitmap.createScaledBitmap(Bitmap.createScaledBitmap(small, 8, 5, true), 64, 36, true);
        BitmapDrawable out = new BitmapDrawable(getResources(), big);
        out.setFilterBitmap(true);
        return out;
    }

    private void showBackdrop(Drawable next) {
        if (next == currentBackdrop) return;
        TransitionDrawable fade = new TransitionDrawable(new Drawable[]{currentBackdrop, next});
        fade.setCrossFadeEnabled(true);
        backdrop.setImageDrawable(fade);
        fade.startTransition(350);
        currentBackdrop = next;
    }

    private int dp(int v) {
        return Math.round(v * getResources().getDisplayMetrics().density);
    }
}
