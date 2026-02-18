// concoredocker.java -- this java file will be the equivalent of concoredocker.py
import java.io.BufferedReader;
import java.io.BufferedWriter;
import java.io.FileReader;
import java.io.FileWriter;
import java.io.IOException;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;

public class concoredocker {
    static String s = "";
    static String olds = "";
    static String inpath = "/in"; // must be absolute path for local
    static String outpath = "/out";
    static int maxtime;
    
    public static int delay = 1; // second
    public static int retrycount = 0;
    public static double simtime;
    public static Map<String, Integer> iport = new HashMap<>();
    public static Map<String, Integer> oport = new HashMap<>();

    public concoredocker(){
        iport = mapParser("concore.iport");
        oport = mapParser("concore.oport");

    }
    public static void main(String[] args) {
        default_maxtime(100);
    }

    private static Map<String, Integer> mapParser(String filename) {
        Map<String, Integer> config = new HashMap<>();
        StringBuilder portstr = new StringBuilder(); // StringBuilder to store file data        
        try (BufferedReader reader = new BufferedReader(new FileReader(filename))) {
            int ch;
            while ((ch = reader.read()) != -1) {
                portstr.append((char) ch); // Add character to string builder
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
        
        portstr.setCharAt(portstr.length() - 1, ','); // Replace last character with comma
        portstr.append("}");
        int i = 0;
        String portname = "";
        String portnum = "";

        while(portstr.charAt(i) != '}'){
            if(portstr.charAt(i) == '\''){
                i++;
                while(portstr.charAt(i) != '\''){
                    portname += portstr.charAt(i);
                    i++;
                }
                config.put(portname,0);
            }
            if(portstr.charAt(i) == ':'){
                i++;
                while(portstr.charAt(i) != ','){
                    portnum += portstr.charAt(i);
                    i++;
                }
                config.put(portname,Integer.parseInt(portnum));
                portname = "";
                portnum = "";
            }
            i++;
        }
        return config;
    }

    //function to compare and determine whether file content has been changed
    public static boolean unchanged() {
        if (olds.equals(s)) {
            s = "";
            return true;
        } else {
            olds = s;
            return false;
        }
    }

    private static ArrayList<Double> parser(String f){
        ArrayList<Double> temp = new ArrayList<>();
        String value = "";
        // Changing last bracket to comma to use comma as a delimiter
        f = f.substring(0, f.length() - 1) + ",";
        for(int i=1;i<f.length();i++){
            if(f.charAt(i) != ','){
                value += f.charAt(i);
            }
            else{
                if(value.length() != 0)
                temp.add(Double.parseDouble(value));

                // reset value
                value = "";
            }
        }
        return temp;
    }

    //accepts the file name as string and returns a string of file content
    public static ArrayList<Double> read(int port, String name, String initstr) {
        String ins = "";
        try {Thread.sleep(1000 * delay);}
        catch(InterruptedException e){
            e.printStackTrace();
        }
        try (BufferedReader reader = new BufferedReader(new FileReader(inpath + String.valueOf(port) + "/" + name))) {
            int ch;
            while ((ch = reader.read()) != -1) {
                ins += ((char) ch); // Add character to string
            }
        }catch(IOException e){
            ins = initstr;
            e.printStackTrace();
        } 


        while(ins.length() == 0){
            try {Thread.sleep(1000 * delay);}
            catch(InterruptedException e){
                e.printStackTrace();
            }
            try (BufferedReader reader = new BufferedReader(new FileReader(inpath + String.valueOf(port) + "/" + name))) {
                int ch;
                while ((ch = reader.read()) != -1) {
                    ins += ((char) ch); // Add character to string
                }
                retrycount++;
            } catch (IOException e) {
                //observed retry count in java from various tests is not calculated yet
                retrycount++;
                System.out.println("Read error");
                e.printStackTrace();
            }
        }
        s += ins;

        ArrayList<Double> inval = new ArrayList<>();
        inval = parser(ins);
        simtime = simtime > inval.get(0) ? simtime : inval.get(0);

        // returning a string with data exluding simtime
        inval.remove(0);
        return inval;
    }

    //write method, accepts a vector double and writes it to the file
    public static void write(int port, String name, ArrayList<Double> val, int delta) {
        try (BufferedWriter writer = new BufferedWriter (new FileWriter(outpath + String.valueOf(port) + "/" + name))){
            val.add(0,simtime+delta);
            writer.write('[');
            for(int i=0;i<val.size()-1;i++){
                writer.write(val.get(i).toString());
                writer.write(',');
            }
            writer.write(val.size()-1);
            writer.write(']');
        } catch (IOException e) {
            System.out.println("skipping +" + outpath + port + " /" + name);
            e.printStackTrace();
        }
    }

    //write method, accepts a string and writes it to the file
    public static void write(int port, String name, String val, int delta) {
        try {Thread.sleep(1000 * delay);}
        catch(InterruptedException e){
            e.printStackTrace();
        }
        try (BufferedWriter writer = new BufferedWriter (new FileWriter(outpath + String.valueOf(port) + "/" + name))){
            writer.write(val);
        } catch (IOException e) {
            System.out.println("skipping +" + outpath + port + " /" + name);
            e.printStackTrace();
        }
    }

    public static void default_maxtime(int defaultValue) {
        try(BufferedReader reader = new BufferedReader(new FileReader(inpath+"1/concore.maxtime"))){
            String line = reader.readLine();
            maxtime = Integer.parseInt(line);
            
        } catch (IOException e) {
            maxtime = defaultValue;
        }
    }

    //Initializing
    public static ArrayList<Double> initval(String simtimeVal) {
        //parsing
        ArrayList<Double> val = new ArrayList<>();

        //determining simtime
        simtime = val.get(0);

        //returning the rest of the values(except simtime) in val
        val.remove(0);
        return val;
    }
}