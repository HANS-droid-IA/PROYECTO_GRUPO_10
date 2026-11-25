package pe.olva.bigdata;

import java.io.IOException;
import java.util.Locale;

import org.apache.hadoop.io.NullWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Reducer;

/**
 * JOB 3 - Fase REDUCE. Publica: dimension, a, b, envios, entregados,
 * pct_cumplimiento_sla, retraso_promedio_h (de los tardíos), ingresos_soles.
 */
public class SlaReducer extends Reducer<Text, Text, NullWritable, Text> {

    private final Text salida = new Text();

    @Override
    protected void reduce(Text clave, Iterable<Text> valores, Context ctx)
            throws IOException, InterruptedException {
        double[] t = SumaCombiner.sumar(valores);
        long envios = Math.round(t[0]);
        long entregados = Math.round(t[1]);
        long aTiempo = Math.round(t[2]);
        long tarde = entregados - aTiempo;
        String[] k = clave.toString().split("\\|");
        salida.set(String.format(Locale.ROOT, "%s,%s,%s,%d,%d,%.2f,%.2f,%.2f",
                k[0], k[1], k[2], envios, entregados,
                entregados == 0 ? 0 : 100.0 * aTiempo / entregados,
                tarde == 0 ? 0 : t[3] / tarde, t[4]));
        ctx.write(NullWritable.get(), salida);
    }
}
