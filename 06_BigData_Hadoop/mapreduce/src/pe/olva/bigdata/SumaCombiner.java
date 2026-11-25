package pe.olva.bigdata;

import java.io.IOException;
import java.util.Locale;

import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Reducer;

/**
 * COMBINER genérico: suma columna a columna valores "a,b,c,..." de la misma clave en el nodo
 * del mapper, para enviar menos datos por la red en la fase shuffle.
 */
public class SumaCombiner extends Reducer<Text, Text, Text, Text> {

    private final Text valor = new Text();

    public static double[] sumar(Iterable<Text> valores) {
        double[] tot = null;
        for (Text v : valores) {
            String[] p = v.toString().split(",");
            if (tot == null) {
                tot = new double[p.length];
            }
            for (int i = 0; i < p.length; i++) {
                tot[i] += Double.parseDouble(p[i]);
            }
        }
        return tot;
    }

    @Override
    protected void reduce(Text clave, Iterable<Text> valores, Context ctx)
            throws IOException, InterruptedException {
        double[] tot = sumar(valores);
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < tot.length; i++) {
            if (i > 0) {
                sb.append(',');
            }
            sb.append(String.format(Locale.ROOT, "%.4f", tot[i]));
        }
        valor.set(sb.toString());
        ctx.write(clave, valor);
    }
}
