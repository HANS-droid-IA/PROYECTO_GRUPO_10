package pe.olva.bigdata;

import java.io.IOException;

import org.apache.hadoop.io.LongWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Mapper;

/**
 * JOB 2 - Fase MAP (segunda pasada sobre la salida del JOB 1).
 * Entrada : "DIMENSION|hub|valor <TAB> 1,horas,mayor12h"
 * Salida  : la misma clave y el mismo valor; el combiner y el reducer suman por clave.
 */
public class AgregadoMapper extends Mapper<LongWritable, Text, Text, Text> {

    private final Text clave = new Text();
    private final Text valor = new Text();

    @Override
    protected void map(LongWritable offset, Text linea, Context ctx)
            throws IOException, InterruptedException {
        String[] p = linea.toString().split("\t");
        if (p.length != 2) {
            return;
        }
        clave.set(p[0]);
        valor.set(p[1]);
        ctx.write(clave, valor);
    }
}
