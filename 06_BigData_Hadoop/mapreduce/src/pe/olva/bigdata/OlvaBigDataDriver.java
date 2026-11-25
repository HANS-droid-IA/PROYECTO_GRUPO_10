package pe.olva.bigdata;

import java.net.URI;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.conf.Configured;
import org.apache.hadoop.fs.FileSystem;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.NullWritable;
import org.apache.hadoop.io.Text;
import org.apache.hadoop.mapreduce.Job;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;
import org.apache.hadoop.util.Tool;
import org.apache.hadoop.util.ToolRunner;

/**
 * DRIVER - encadena los tres jobs MapReduce del análisis Big Data de Olva Courier.
 *
 * Pregunta analítica: ¿en qué hubs, horas y meses se concentra el tiempo de permanencia
 * de los paquetes y cómo se refleja en el cumplimiento del plazo (SLA)?
 *
 *   JOB 1 permanencia : evento_tracking -> estancias por envío y hub
 *   JOB 2 agregado    : estancias -> permanencia promedio y % > 12 h por hub/hora/mes/día
 *   JOB 3 sla         : envio -> % de cumplimiento, retraso e ingresos por servicio/ruta
 *
 * Uso: hadoop jar olva-bigdata.jar <entrada_hdfs> <salida_hdfs>
 *      <entrada_hdfs> contiene evento_tracking/, envio/ y catalogos/
 *      (hub, ciudad, region, tipo_servicio).
 */
public class OlvaBigDataDriver extends Configured implements Tool {

    private static final String[] CATALOGOS =
            {"hub.csv", "ciudad.csv", "region.csv", "tipo_servicio.csv"};

    private void agregarCatalogos(Job job, Path entrada) throws Exception {
        for (String c : CATALOGOS) {
            // "#nombre" crea un enlace simbólico con ese nombre en el directorio de cada task
            String ruta = new Path(entrada, "catalogos/" + c).toUri().toString();
            URI uri = new URI(ruta + "#" + c);
            job.addCacheFile(uri);
        }
    }

    private boolean ejecutar(Job job) throws Exception {
        boolean ok = job.waitForCompletion(true);
        if (!ok) {
            System.err.println("Falló el job: " + job.getJobName());
        }
        return ok;
    }

    @Override
    public int run(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("Uso: OlvaBigDataDriver <entrada_hdfs> <salida_hdfs>");
            return 2;
        }
        Configuration conf = getConf();
        Path entrada = new Path(args[0]);
        Path salida = new Path(args[1]);
        FileSystem fs = salida.getFileSystem(conf);
        if (fs.exists(salida)) {
            fs.delete(salida, true);   // permite volver a ejecutar el análisis
        }
        Path estancias = new Path(salida, "tmp_estancias");

        // ---------------- JOB 1: permanencia por envío ----------------
        Job j1 = Job.getInstance(conf, "olva-1-permanencia-por-envio");
        j1.setJarByClass(OlvaBigDataDriver.class);
        j1.setMapperClass(PermanenciaMapper.class);
        j1.setReducerClass(PermanenciaReducer.class);
        j1.setOutputKeyClass(Text.class);
        j1.setOutputValueClass(Text.class);
        j1.setNumReduceTasks(4);
        agregarCatalogos(j1, entrada);
        FileInputFormat.addInputPath(j1, new Path(entrada, "evento_tracking"));
        FileOutputFormat.setOutputPath(j1, estancias);
        if (!ejecutar(j1)) {
            return 1;
        }

        // ---------------- JOB 2: indicadores de permanencia ----------------
        Job j2 = Job.getInstance(conf, "olva-2-permanencia-agregada");
        j2.setJarByClass(OlvaBigDataDriver.class);
        j2.setMapperClass(AgregadoMapper.class);
        j2.setCombinerClass(SumaCombiner.class);
        j2.setReducerClass(AgregadoReducer.class);
        j2.setMapOutputKeyClass(Text.class);
        j2.setMapOutputValueClass(Text.class);
        j2.setOutputKeyClass(NullWritable.class);
        j2.setOutputValueClass(Text.class);
        j2.setNumReduceTasks(1);
        FileInputFormat.addInputPath(j2, estancias);
        FileOutputFormat.setOutputPath(j2, new Path(salida, "permanencia_hub"));
        if (!ejecutar(j2)) {
            return 1;
        }

        // ---------------- JOB 3: cumplimiento del SLA ----------------
        Job j3 = Job.getInstance(conf, "olva-3-cumplimiento-sla");
        j3.setJarByClass(OlvaBigDataDriver.class);
        j3.setMapperClass(SlaMapper.class);
        j3.setCombinerClass(SumaCombiner.class);
        j3.setReducerClass(SlaReducer.class);
        j3.setMapOutputKeyClass(Text.class);
        j3.setMapOutputValueClass(Text.class);
        j3.setOutputKeyClass(NullWritable.class);
        j3.setOutputValueClass(Text.class);
        j3.setNumReduceTasks(1);
        agregarCatalogos(j3, entrada);
        FileInputFormat.addInputPath(j3, new Path(entrada, "envio"));
        FileOutputFormat.setOutputPath(j3, new Path(salida, "cumplimiento_sla"));
        if (!ejecutar(j3)) {
            return 1;
        }

        fs.delete(estancias, true);
        System.out.println("Resultados en: " + salida);
        return 0;
    }

    public static void main(String[] args) throws Exception {
        System.exit(ToolRunner.run(new Configuration(), new OlvaBigDataDriver(), args));
    }
}
