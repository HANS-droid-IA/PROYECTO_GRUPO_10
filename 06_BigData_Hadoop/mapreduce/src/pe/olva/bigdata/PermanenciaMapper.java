package pe.olva.bigdata;

import java.io.IOException;

import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Mapper;

/**
 * JOB 1 - Fase MAP.
 * Entrada : evento_tracking.csv (id_evento, id_envio, tipo_evento, id_hub, id_empleado,
 *           id_despacho, fecha_hora, observacion)
 * Salida  : clave = id_envio ; valor = tipo_evento|id_hub|fecha_hora
 * Solo interesan las llegadas y salidas de hub: con ellas el reducer reconstruye cuánto
 * tiempo permaneció cada paquete dentro de cada hub.
 */
public class PermanenciaMapper extends Mapper<LongWritable, Text, Text, Text> {

    private final Text envio = new Text();
    private final Text valor = new Text();

    @Override
    protected void map(LongWritable offset, Text linea, Context ctx)
            throws IOException, InterruptedException {
        String s = linea.toString();
        if (s.isEmpty() || Util.esCabecera(s)) {
            return;
        }
        String[] c = Util.csv(s);
        if (c.length < 7) {
            ctx.getCounter("OLVA", "LINEAS_MALFORMADAS").increment(1);
            return;
        }
        String tipo = c[2];
        if (!"LLEGADA_HUB".equals(tipo) && !"SALIDA_HUB".equals(tipo)) {
            return;
        }
        envio.set(c[1]);
        valor.set(tipo + "|" + c[3] + "|" + c[6]);
        ctx.write(envio, valor);
        ctx.getCounter("OLVA", "EVENTOS_HUB_LEIDOS").increment(1);
    }
}
