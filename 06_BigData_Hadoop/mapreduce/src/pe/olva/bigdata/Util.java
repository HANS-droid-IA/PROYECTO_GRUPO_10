package pe.olva.bigdata;

import java.io.BufferedReader;
import java.io.FileInputStream;
import java.io.IOException;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.text.ParseException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Date;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * Utilidades comunes: lectura CSV, fechas y catálogos de la caché distribuida.
 */
public final class Util {

    private Util() { }

    /** Separa una línea CSV respetando campos entre comillas dobles. */
    public static String[] csv(String linea) {
        List<String> campos = new ArrayList<>();
        StringBuilder sb = new StringBuilder();
        boolean comillas = false;
        for (int i = 0; i < linea.length(); i++) {
            char c = linea.charAt(i);
            if (c == '"') {
                if (comillas && i + 1 < linea.length() && linea.charAt(i + 1) == '"') {
                    sb.append('"');
                    i++;
                } else {
                    comillas = !comillas;
                }
            } else if (c == ',' && !comillas) {
                campos.add(sb.toString());
                sb.setLength(0);
            } else {
                sb.append(c);
            }
        }
        campos.add(sb.toString());
        return campos.toArray(new String[0]);
    }

    /**
     * Las fechas vienen como '2026-04-01 13:46:53-05' (hora de Lima); se usan los 19 primeros
     * caracteres.
     */
    public static Date fecha(String s) {
        if (s == null || s.length() < 19) {
            return null;
        }
        try {
            SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd HH:mm:ss");
            f.setLenient(false);
            return f.parse(s.substring(0, 19));
        } catch (ParseException e) {
            return null;
        }
    }

    public static double horasEntre(Date a, Date b) {
        return (b.getTime() - a.getTime()) / 3600000.0;
    }

    /**
     * Lee un catálogo CSV enviado por la caché distribuida (enlace simbólico en el
     * directorio del task) y devuelve un mapa columnaClave -> fila completa.
     */
    public static Map<String, String[]> catalogo(String archivo, int columnaClave)
            throws IOException {
        Map<String, String[]> m = new HashMap<>();
        try (BufferedReader br = new BufferedReader(
                new InputStreamReader(new FileInputStream(archivo),
                        StandardCharsets.UTF_8))) {
            String linea = br.readLine(); // cabecera
            while ((linea = br.readLine()) != null) {
                String[] c = csv(linea);
                m.put(c[columnaClave], c);
            }
        }
        return m;
    }

    public static boolean esCabecera(String linea) {
        return linea.startsWith("id_");
    }
}
