import android.util.Log;

public class DebugUtils {
    public static void log(String tag, String message) {
        StackTraceElement caller = Thread.currentThread().getStackTrace()[4]; // Get calling function
        String className = caller.getClassName();  // Get calling class
        String methodName = caller.getMethodName(); // Get calling function
        int lineNumber = caller.getLineNumber(); // Get line number

        Log.d(tag, "[" + className + "." + methodName + ":" + lineNumber + "] " + message);
    }
}