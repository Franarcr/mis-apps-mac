package local.fran.iniciotv;

import android.app.admin.DeviceAdminReceiver;

/**
 * Administrador del dispositivo con un solo permiso: apagar la pantalla (lockNow), para el botón «Apagar TV».
 * Se activa una vez desde el Mac: adb shell dpm set-active-admin local.fran.iniciotv/.PowerAdmin
 */
public class PowerAdmin extends DeviceAdminReceiver { }
