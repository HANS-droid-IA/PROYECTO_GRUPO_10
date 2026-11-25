package pe.olva.bigdata;

import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Calendar;
import java.util.Collections;
import java.util.Date;
import java.util.List;
import java.util.Map;

import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Reducer;

/**
 * JOB 1 - Fase REDUCE.
 * Recibe todos los eventos de llegada/salida de UN envío, los ordena por fecha y empareja
 * cada LLEGADA_HUB con la siguiente SALIDA_HUB del mismo hub: la diferencia es el tiempo
 * de permanencia. Solo se miden hubs de clasificación (HUB_CENTRAL y HUB_REGIONAL).
 *
 * Salida (clave -> valor "1,horas,mayor12h"), una línea por dimensión de análisis:
 *   HORA|codigo_hub|hora_de_llegada   -> permanencia según la hora de llegada
 *   MES|codigo_hub|aaaa-mm            -> permanencia según el mes (estacionalidad)
 *   DIA|codigo_hub|dia_de_semana      -> permanencia según el día de la semana
 */
public class PermanenciaReducer extends Reducer<Text, Text, Text, Text> {

    private static final String[] DIAS = {"", "7-Domingo", "1-Lunes", "2-Martes",
        "3-Miercoles", "4-Jueves", "5-Viernes", "6-Sabado"};
    private Map<String, String[]> hubs;   // id_hub -> fila de hub.csv
    private final Text clave = new Text();
    private final Text valor = new Text();

    @Override
    protected void setup(Context ctx) throws IOException {
        hubs = Util.catalogo("hub.csv", 0);   // archivo de la caché distribuida
    }

    private static final class Ev implements Comparable<Ev> {
        final String tipo;
        final String hub;
        final Date fecha;

        Ev(String tipo, String hub, Date fecha) {
            this.tipo = tipo;
            this.hub = hub;
            this.fecha = fecha;
        }

        @Override
        public int compareTo(Ev o) {
            int c = fecha.compareTo(o.fecha);
            // a igual hora, la llegada va antes que la salida
            return c != 0 ? c : (tipo.startsWith("LLEGADA") ? -1 : 1);
        }
    }

    @Override
    protected void reduce(Text envio, Iterable<Text> valores, Context ctx)
            throws IOException, InterruptedException {
        List<Ev> eventos = new ArrayList<>();
        for (Text v : valores) {
            String[] p = v.toString().split("\\|");
            Date f = Util.fecha(p[2]);
            if (f != null) {
                eventos.add(new Ev(p[0], p[1], f));
            }
        }
        Collections.sort(eventos);
        SimpleDateFormat mes = new SimpleDateFormat("yyyy-MM");
        Calendar cal = Calendar.getInstance();
        for (int i = 0; i < eventos.size(); i++) {
            Ev lleg = eventos.get(i);
            if (!"LLEGADA_HUB".equals(lleg.tipo)) {
                continue;
            }
            String[] hub = hubs.get(lleg.hub);
            if (hub == null || "AGENCIA".equals(hub[3])) {
                continue;
            }
            for (int j = i + 1; j < eventos.size(); j++) {
                Ev sal = eventos.get(j);
                if ("SALIDA_HUB".equals(sal.tipo) && sal.hub.equals(lleg.hub)) {
                    double horas = Util.horasEntre(lleg.fecha, sal.fecha);
                    String h = String.format(java.util.Locale.ROOT, "%.4f", horas);
                    String v = "1," + h + "," + (horas > 12 ? 1 : 0);
                    valor.set(v);
                    cal.setTime(lleg.fecha);
                    String codigo = hub[1];
                    int hora = cal.get(Calendar.HOUR_OF_DAY);
                    clave.set(String.format("HORA|%s|%02d", codigo, hora));
                    ctx.write(clave, valor);
                    clave.set("MES|" + codigo + "|" + mes.format(lleg.fecha));
                    ctx.write(clave, valor);
                    clave.set("DIA|" + codigo + "|" + DIAS[cal.get(Calendar.DAY_OF_WEEK)]);
                    ctx.write(clave, valor);
                    ctx.getCounter("OLVA", "ESTANCIAS_EN_HUB").increment(1);
                    break;
                }
            }
        }
    }
}
