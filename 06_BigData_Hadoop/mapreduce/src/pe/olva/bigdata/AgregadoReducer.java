package pe.olva.bigdata;

import java.io.IOException;
import java.util.Locale;

import org.apache.hadoop.io.NullWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Reducer;

/**
 * JOB 2 - Fase REDUCE.
 * Suma (estancias, horas, estancias>12h) por clave y publica el indicador final:
 *   dimension, hub, valor, estancias, permanencia_promedio_h, pct_mayor_12h
 */
public class AgregadoReducer extends Reducer<Text, Text, NullWritable, Text> {

    private final Text salida = new Text();

    @Override
    protected void reduce(Text clave, Iterable<Text> valores, Context ctx)
            throws IOException, InterruptedException {
        double[] t = SumaCombiner.sumar(valores);
        long n = Math.round(t[0]);
        String[] k = clave.toString().split("\\|");
        salida.set(String.format(Locale.ROOT, "%s,%s,%s,%d,%.2f,%.2f",
                k[0], k[1], k[2], n, t[1] / n, 100.0 * t[2] / n));
        ctx.write(NullWritable.get(), salida);
    }
}
