package pe.olva.bigdata;

import java.io.IOException;
import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.Map;

import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Mapper;

/**
 * JOB 3 - Fase MAP: cumplimiento del SLA (plazo comprometido) por servicio y ruta.
 * Entrada : envio.csv (0 id_envio, 4 id_servicio, 5 id_hub_origen, 6 id_hub_destino,
 *           8 fecha_registro, 9 fecha_compromiso, 13 monto_total, 14 fecha_entrega, ...)
 * Join en el lado del map (map-side join) con los catálogos hub, ciudad, region y
 * tipo_servicio enviados por la caché distribuida.
 * Salida  : clave = DIMENSION|a|b
 *           valor = "envios,entregados,a_tiempo,horas_retraso,ingresos_soles"
 */
public class SlaMapper extends Mapper<LongWritable, Text, Text, Text> {

    private Map<String, String[]> hubs;
    private Map<String, String[]> ciudades;
    private Map<String, String[]> regiones;
    private Map<String, String[]> servicios;
    private final Text clave = new Text();
    private final Text valor = new Text();
    private final SimpleDateFormat mes = new SimpleDateFormat("yyyy-MM");

    @Override
    protected void setup(Context ctx) throws IOException {
        hubs = Util.catalogo("hub.csv", 0);
        ciudades = Util.catalogo("ciudad.csv", 0);
        regiones = Util.catalogo("region.csv", 0);
        servicios = Util.catalogo("tipo_servicio.csv", 0);
    }

    private String region(String idHub) {
        String[] h = hubs.get(idHub);
        String[] c = h == null ? null : ciudades.get(h[4]);
        String[] r = c == null ? null : regiones.get(c[3]);
        return r == null ? "?" : r[2];
    }

    @Override
    protected void map(LongWritable offset, Text linea, Context ctx)
            throws IOException, InterruptedException {
        String s = linea.toString();
        if (s.isEmpty() || Util.esCabecera(s)) {
            return;
        }
        String[] c = Util.csv(s);
        if (c.length < 15) {
            ctx.getCounter("OLVA", "LINEAS_MALFORMADAS").increment(1);
            return;
        }
        String[] sv = servicios.get(c[4]);
        String servicio = sv == null ? "?" : sv[1];
        Date registro = Util.fecha(c[8]);
        Date compromiso = Util.fecha(c[9]);
        Date entrega = Util.fecha(c[14]);
        double monto = Double.parseDouble(c[13]);
        int entregado = entrega != null ? 1 : 0;
        int aTiempo = entrega != null && !entrega.after(compromiso) ? 1 : 0;
        double retraso = entrega != null && aTiempo == 0
                ? Util.horasEntre(compromiso, entrega) : 0;
        valor.set(String.format(Locale.ROOT, "1,%d,%d,%.4f,%.2f",
                entregado, aTiempo, retraso, monto));

        String ruta = region(c[5]) + " -> " + region(c[6]);
        clave.set("SERVICIO_RUTA|" + servicio + "|" + ruta);
        ctx.write(clave, valor);
        clave.set("SERVICIO|" + servicio + "|TOTAL");
        ctx.write(clave, valor);
        clave.set("MES|" + (registro == null ? "?" : mes.format(registro)) + "|TOTAL");
        ctx.write(clave, valor);
        clave.set("AGENCIA_ORIGEN|" + hubs.get(c[5])[1] + "|TOTAL");
        ctx.write(clave, valor);
        ctx.getCounter("OLVA", "ENVIOS_LEIDOS").increment(1);
    }
}
