package local.fran.iniciotv;

import android.app.Activity;
import android.app.admin.DevicePolicyManager;
import android.content.ComponentName;
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
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.List;
import java.util.Locale;
import java.util.Set;

/**
 * Pantalla de inicio minimalista al estilo Apple TV: hora arriba y tres filas.
 * Favoritas · Más apps · TV (TV en vivo, entradas y configuración).
 */
public class HomeActivity extends Activity {

    /**
     * La pantalla, fila por fila y en 5 columnas, tal como la dibujó Fran. Cada casilla es un acceso del TV
     * (TV, CABLE, APPLE, INPUTS, SETTINGS, POWER), una app por su paquete (o varios posibles, separados por «|»,
     * o «nombre:» para buscarla por su nombre), o null para dejarla vacía.
     * Las apps que no están aquí no se muestran.
     */
    private static final String[][] LAYOUT = {
            {null, "TV", "CABLE", "APPLE", null},
            {"com.netflix.ninja",                       // Netflix
             "com.google.android.youtube.tv",           // YouTube
             "com.apple.atve.androidtv.appletv",        // Apple TV (la app)
             "com.cbs.ott|nombre:Paramount",            // Paramount+
             "com.crunchyroll.crunchyroid|nombre:Crunchyroll"},
            {"com.tubitv|nombre:Tubi",
             "com.google.android.youtube.tvmusic|nombre:YouTube Music",
             "com.amazon.amazonvideo.livingroom",       // Prime Video
             "com.disney.disneyplus",                   // Disney+
             "com.wbd.stream|com.hbo.hbomax"},          // HBO Max
            {null, "INPUTS", "SETTINGS", "POWER", null},
    };

    /** Al volver al inicio, la selección empieza en esta casilla (fila, columna): «TV en vivo». */
    private static final int FOCUS_ROW = 0, FOCUS_COL = 1;

    // Entradas del TV (ver `adb shell dumpsys tv_input`): sintonizador de antena y HDMI 2, donde entra el cable.
    private static final String ANTENNA = "com.mediatek.tvinput/.tuner.TunerInputService/HW0";
    private static final String CABLE = "com.mediatek.tvinput/.hdmi.HDMIInputService/HW5";
    /** HDMI 1, donde está la cajita Apple TV (se usa si el TV no la reconoce por su nombre). */
    private static final String APPLE_TV_INPUT = "com.mediatek.tvinput/.hdmi.HDMIInputService/HW4";

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

        // Las filas, centradas en la pantalla.
        rows = new LinearLayout(this);
        rows.setOrientation(LinearLayout.VERTICAL);
        rows.setClipChildren(false);
        FrameLayout.LayoutParams rlp = new FrameLayout.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT, Gravity.CENTER_VERTICAL);
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
        Map<String, App> installed = new HashMap<>();
        for (ResolveInfo ri : pm.queryIntentActivities(q, 0)) {
            ActivityInfo ai = ri.activityInfo;
            if (installed.containsKey(ai.packageName)) continue;
            App a = new App();
            a.pkg = ai.packageName;
            a.name = String.valueOf(ri.loadLabel(pm));
            a.banner = ai.loadBanner(pm);
            if (a.banner == null) a.banner = ai.applicationInfo.loadBanner(pm);
            a.icon = ri.loadIcon(pm);
            a.launch = new Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LEANBACK_LAUNCHER)
                    .setClassName(ai.packageName, ai.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            installed.put(a.pkg, a);
        }

        rows.removeAllViews();
        for (String[] line : LAYOUT) {
            LinearLayout row = newRow(dp(4));
            for (String slot : line) {
                View cell = slot == null ? null : cell(slot, installed, pm);
                row.addView(cell != null ? cell : empty());
            }
        }
        focusFirst();
    }

    /** Arma la casilla de un acceso del TV o de una app; null si esa app no está instalada. */
    private View cell(String slot, Map<String, App> installed, PackageManager pm) {
        switch (slot) {
            case "TV": return tile("TV en vivo", null, getDrawable(R.drawable.ic_tv), input(ANTENNA));
            case "CABLE": return tile("Cable", null, getDrawable(R.drawable.ic_cable), input(CABLE));
            case "APPLE": {
                return tile("Apple TV", null, getDrawable(R.drawable.ic_apple), input(appleTvInput()));
            }
            case "INPUTS": {
                Intent inputs = new Intent("com.android.tv.action.VIEW_INPUTS").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                return inputs.resolveActivity(pm) != null ? tile("Entradas", null, getDrawable(R.drawable.ic_input), inputs) : null;
            }
            case "SETTINGS":
                return tile("Configuración", null, getDrawable(R.drawable.ic_gear),
                        new Intent(android.provider.Settings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK));
            case "POWER": {
                View c = tile("Apagar TV", null, getDrawable(R.drawable.ic_power), null);
                ((ViewGroup) c).getChildAt(0).setOnClickListener(v -> powerOff());
                return c;
            }
        }
        for (String option : slot.split("\\|")) {
            App a = null;
            if (option.startsWith("nombre:")) {
                String wanted = option.substring(7).toLowerCase(Locale.ROOT);
                for (App x : installed.values()) if (x.name.toLowerCase(Locale.ROOT).contains(wanted)) { a = x; break; }
            } else {
                a = installed.get(option);
            }
            if (a != null) return tile(a.name, a.banner, a.banner == null ? a.icon : null, a.launch);
        }
        return null;
    }

    /** Casilla vacía del mismo tamaño, para que las columnas queden alineadas. */
    private View empty() {
        View v = new View(this);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(150), dp(106));
        lp.setMargins(dp(10), 0, dp(10), 0);
        v.setLayoutParams(lp);
        return v;
    }

    /** La entrada de la cajita Apple TV: la que el TV reconoce con ese nombre (HDMI-CEC) o, si no, la fija. */
    private String appleTvInput() {
        try {
            android.media.tv.TvInputManager tim = (android.media.tv.TvInputManager) getSystemService(TV_INPUT_SERVICE);
            for (android.media.tv.TvInputInfo info : tim.getTvInputList()) {
                CharSequence label = info.loadLabel(this);
                CharSequence custom = info.loadCustomLabel(this);
                String text = (label + " " + custom).toLowerCase(Locale.ROOT);
                if (text.contains("apple")) return info.getParentId() != null ? info.getParentId() : info.getId();
            }
        } catch (Exception ignored) { }
        return APPLE_TV_INPUT;
    }

    /** Apaga el TV (lo deja en reposo, como el botón del control). */
    private void powerOff() {
        DevicePolicyManager dpm = (DevicePolicyManager) getSystemService(DEVICE_POLICY_SERVICE);
        ComponentName admin = new ComponentName(this, PowerAdmin.class);
        if (dpm.isAdminActive(admin)) {
            dpm.lockNow();
        } else {
            // Aún no tiene permiso: lo pide una vez en la pantalla del TV.
            Intent ask = new Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN)
                    .putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, admin)
                    .putExtra(DevicePolicyManager.EXTRA_ADD_EXPLANATION, "Para que el botón «Apagar TV» pueda apagar el televisor.");
            try { startActivity(ask); } catch (Exception ignored) { }
        }
    }

    private LinearLayout newRow(int top) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setClipChildren(false);
        row.setClipToPadding(false);
        row.setGravity(Gravity.CENTER_HORIZONTAL);
        row.setPadding(0, top, 0, 0);
        rows.addView(row);
        return row;
    }

    /** Abre directamente una entrada del TV (sintonizador o HDMI) por su id. */
    private static Intent input(String inputId) {
        return new Intent(Intent.ACTION_VIEW, android.media.tv.TvContract.buildChannelUriForPassthroughInput(inputId))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
    }

    /** Al volver al inicio, la selección empieza en «TV en vivo». */
    private void focusFirst() {
        rows.post(() -> {
            if (rows.getChildCount() <= FOCUS_ROW) return;
            ViewGroup row = (ViewGroup) rows.getChildAt(FOCUS_ROW);
            if (row.getChildCount() <= FOCUS_COL) return;
            View cell = row.getChildAt(FOCUS_COL);
            if (cell instanceof ViewGroup && ((ViewGroup) cell).getChildCount() > 0) ((ViewGroup) cell).getChildAt(0).requestFocus();
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
        if (banner != null) name_.setText(name);
        name_.setTextColor(Color.WHITE);
        name_.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        name_.setGravity(Gravity.CENTER);
        name_.setSingleLine(true);
        name_.setAlpha(0f);
        Drawable blurred = blurred(banner);
        t.setOnFocusChangeListener((v, has) -> {
            float s = has ? 1.15f : 1f;
            if (banner == null) bg.setColor(has ? 0xFF4A5868 : 0xFF1E2630);
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
        lp.setMargins(dp(10), 0, dp(10), 0);
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
