/**
 *   D symbol name demangling
 *
 *   Attempts to demangle D symbols generated by the DMD frontend.
 *   (Which is not always technically possible)
 *
 *  Copyright: Copyright (C) 2007-2008 Zygfryd (aka Hxal). All rights reserved.
 *  License:   tango license, apache 2.0
 *  Authors:   Zygfryd (aka Hxal), Fawzi
 *
 */

module tango.core.stacktrace.Demangler;

import tango.core.Traits: ctfe_i2a;
import tango.stdc.string: memmove,memcpy;
import tango.stdc.stdio: printf;

debug(traceDemangler) import tango.io.Stdout;

uint toUint(char[]s){
    uint res=0;
    for (int i=0;i<s.length;++i){
        if (s[i]>='0'&& s[i]<='9'){
            res*=10;
            res+=s[i]-'0';
        } else {
            assert(false);
            return res;
        }
    }
    return res;
}

/**
 *   Flexible demangler
 *   Attempts to demangle D symbols generated by the DMD frontend.
 *   (Which is not always technically possible)
 */
public class Demangler
{
    /** How deeply to recurse printing template parameters,
      * for depths greater than this, an ellipsis is used */
    uint templateExpansionDepth = 1;

    /** Skip default members of templates (sole members named after
      * the template) */
    bool foldDefaults = true;

    /** Print types of functions being part of the main symbol */
    bool expandFunctionTypes = false;

    /** For composite types, print the kind (class|struct|etc.) of the type */
    bool printTypeKind = false;

    /** sets the verbosity level of the demangler (template expansion level,...) */
    public void verbosity (uint level)
    {
        switch (level)
        {
            case 0:
                templateExpansionDepth = 0;
                expandFunctionTypes = false;
                printTypeKind = false;
                break;

            case 1:
                templateExpansionDepth = 1;
                expandFunctionTypes = false;
                printTypeKind = false;
                break;

            case 2:
                templateExpansionDepth = 1;
                expandFunctionTypes = false;
                printTypeKind = true;
                break;

            case 3:
                templateExpansionDepth = 1;
                expandFunctionTypes = true;
                printTypeKind = true;
                break;

            default:
                templateExpansionDepth = level - 2;
                expandFunctionTypes = true;
                printTypeKind = true;
        }
    }

    /** creates a demangler */
    this ()
    {
        verbosity (1);
    }

    /** creates a demangler with the given verbosity level */
    this (uint verbosityLevel)
    {
        verbosity (verbosityLevel);
    }
    
    /** demangles the given string */
    public char[] demangle (char[] input)
    {
        char[4096] buf=void;
        auto res=DemangleInstance(this,input,buf);
        if (res.mangledName() && res.input.length==0){
            return res.slice.dup;
        } else {
            if (res.slice.length) res.output.append(" ");
            if (res.type() && res.input.length==0){
                return res.slice.dup;
            } else {
                return input;
            }
        }
    }

    /** demangles the given string using output to hold the result */
    public char[] demangle (char[] input, char[] output)
    {
        auto res=DemangleInstance(this,input,output);
        if (res.mangledName () && res.input.length==0) {
            return res.slice;
        } else {
            if (res.slice.length) res.output.append(" ");
            if (res.type() && res.input.length==0) {
                return res.slice;
            } else {
                return input;
            }
        }
    }

    /// this represents a single demangling request, and is the place where the real work is done
    /// some more cleanup would probably be in order (maybe remove Buffer)
    struct DemangleInstance{
        debug(traceDemangler) private char[][] _trace;
        private char[] input;
        private uint _templateDepth;
        Buffer output;
        Demangler prefs;
        
        struct BufState{
            DemangleInstance* dem;
            char[] input;
            size_t len;
            static BufState opCall(DemangleInstance* dem){
                BufState res;
                res.dem=dem;
                res.len=dem.output.length;
                res.input=dem.input;
                return res;
            }
            // resets input and output buffers and returns false
            bool reset(){
                dem.output.length=len;
                dem.input=input;
                return false;
            }
            // resets only the output buffer and returns false
            bool resetOutput(){
                dem.output.length=len;
                return false;
            }
            char[] sliceFrom(){
                return dem.output.data[len..dem.output.length];
            }
        }
        
        BufState checkpoint(){
            return BufState(this);
        }

        static DemangleInstance opCall(Demangler prefs,char[] input,char[]output){
            DemangleInstance res;
            res.prefs=prefs;
            res.input=input;
            res._templateDepth=0;
            res.output.data=output;
            debug(traceDemangler) res._trace=null;
            return res;
        }

        debug (traceDemangler)
        {
            private void trace (char[] where)
            {
                if (_trace.length > 500)
                    throw new Exception ("Infinite recursion");
                
                int len=_trace.length;
                char[] spaces = "            ";
                spaces=spaces[0 .. ((len<spaces.length)?len:spaces.length)];
                if (input.length < 50)
                    Stdout.formatln ("{}{} : {{{}}", spaces, where, input);
                else
                    Stdout.formatln ("{}{} : {{{}}", spaces, where, input[0..50]);
                _trace ~= where;
            }

            private void report (T...) (char[] fmt, T args)
            {
                int len=_trace.length;
                char[] spaces = "            ";
                spaces=spaces[0 .. ((len<spaces.length)?len:spaces.length)];
                Stdout (spaces);
                Stdout.formatln (fmt, args);
            }

            private void trace (bool result)
            {
                //auto tmp = _trace[$-1];
                _trace = _trace[0..$-1];
                int len=_trace.length;
                char[] spaces = "            ";
                spaces=spaces[0 .. ((len<spaces.length)?len:spaces.length)];
                Stdout(spaces);
                if (!result)
                    Stdout.formatln ("fail");
                else
                    Stdout.formatln ("success");
            }
        }

        char[] slice(){
            return output.slice;
        }

        private char[] consume (uint amt)
        {
            char[] tmp = input[0 .. amt];
            input = input[amt .. $];
            return tmp;
        }

        bool mangledName ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("mangledName");
            
            if (input.length<2)
                return false;
            if (input[0]=='D'){
                consume(1);
            } else if (input[0..2] == "_D") {
                consume(2);
            } else {
                return false;
            }

            if (! typedqualifiedName ())
                return false;

            if (input.length > 0) {
                auto pos1=checkpoint();
                output.append("<");
                if (! type ())
                    pos1.reset(); // return false??
                else if (prefs.printTypeKind){
                    output.append(">");
                } else {
                    pos1.resetOutput();
                }
            }

            //Stdout.formatln ("mangledName={}", namebuf.slice);

            return true;
        }

        bool typedqualifiedName ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("typedqualifiedName");

            auto pos=checkpoint();
            if (! symbolName ())
                return false;
            char[] car=pos.sliceFrom();
            
            // undocumented
            pos=checkpoint();
            output.append ("{");
            if (typeFunction ()){
                if (!prefs. expandFunctionTypes){
                    pos.resetOutput();
                } else {
                    output.append ("}");
                }
            } else {
                pos.reset();
            }

            pos=checkpoint();
            output.append (".");
            if (typedqualifiedName ())
            {
                if (prefs.foldDefaults && car.length<pos.sliceFrom().length &&
                    car==pos.sliceFrom()[1..car.length+1]){
                    pos.resetOutput();
                }
            } else {
                pos.reset();
            }

            return true;
        }

        bool qualifiedName (bool aliasHack = false)
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace (aliasHack ? "qualifiedNameAH" : "qualifiedName");

            auto pos=checkpoint();
            if (! symbolName (aliasHack))
                return false;
            char[] car=pos.sliceFrom();

            auto pos1=checkpoint();
            output.append (".");
            if (typedqualifiedName ())
            {
                char[] cdr=pos1.sliceFrom()[1..$];
                if (prefs.foldDefaults && cdr.length>=car.length && cdr[0..car.length]==car){
                    pos1.resetOutput();
                }
            } else {
                pos1.reset();
            }

            return true;
        }

        bool symbolName ( bool aliasHack = false)
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace (aliasHack ? "symbolNameAH" : "symbolName");

    //      if (templateInstanceName (output))
    //          return true;

            if (aliasHack){
                if (lNameAliasHack ())
                    return true;
            }
            else
            {
                if (lName ())
                    return true;
            }

            return false;
        }

        bool lName ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("lName");
            auto pos=checkpoint;
            uint chars;
            if (! number (chars))
                return false;

            char[] original = input;
            input = input[0 .. chars];
            uint len = input.length;
            if (templateInstanceName())
            {
                input = original[len - input.length .. $];
                return true;
            }
            input = original;

            if(!name (chars)){
                return pos.reset();
            }
            return true;
        }

        /* this hack is ugly and guaranteed to break, but the symbols
           generated for template alias parameters are broken:
           the compiler generates a symbol of the form S(number){(number)(name)}
           with no space between the numbers; what we do is try to match
           different combinations of division between the concatenated numbers */

        bool lNameAliasHack ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("lNameAH");

    //      uint chars;
    //      if (! number (chars))
    //          return false;

            uint chars;
            auto pos=checkpoint();
            if (! numberNoParse ())
                return false;
            char[10] numberBuf;
            char[] str = pos.sliceFrom();
            if (str.length>numberBuf.length){
                return pos.reset();
            }
            numberBuf[0..str.length]=str;
            str=numberBuf[0..str.length];
            pos.resetOutput();
            
            int i = 0;

            bool done = false;

            char[] original = input;
            char[] working = input;

            while (done == false)
            {
                if (i > 0)
                {
                    input = working = original[0 .. toUint(str[0..i])];
                }
                else
                    input = working = original;

                chars = toUint(str[i..$]);

                if (chars < input.length && chars > 0)
                {
                    // cut the string from the right side to the number
                    // char[] original = input;
                    // input = input[0 .. chars];
                    // uint len = input.length;
                    debug(traceDemangler) report ("trying {}/{}", chars, input.length);
                    done = templateInstanceName ();
                    //input = original[len - input.length .. $];

                    if (!done)
                    {
                        input = working;
                        debug(traceDemangler) report ("trying {}/{}", chars, input.length);
                        done = name (chars);
                    }

                    if (done)
                    {
                        input = original[working.length - input.length .. $];
                        return true;
                    }
                    else
                        input = original;
                }

                i += 1;
                if (i == str.length)
                    return false;
            }

            return true;
        }

        bool number (ref uint value)
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("number");

            if (input.length == 0)
                return false;

            value = 0;
            if (input[0] >= '0' && input[0] <= '9')
            {
                while (input.length > 0 && input[0] >= '0' && input[0] <= '9')
                {
                    value = value * 10 + cast(uint) (input[0] - '0');
                    consume (1);
                }
                return true;
            }
            else
                return false;
        }

        bool numberNoParse ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("numberNP");

            if (input.length == 0)
                return false;

            if (input[0] >= '0' && input[0] <= '9')
            {
                while (input.length > 0 && input[0] >= '0' && input[0] <= '9')
                {
                    output.append (input[0]);
                    consume (1);
                }
                return true;
            }
            else
                return false;
        }

        bool name (uint count)
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("name");

            //if (input.length >= 3 && input[0 .. 3] == "__T")
            //  return false; // workaround

            if (count > input.length)
                return false;

            char[] name = consume (count);
            output.append (name);
            debug(traceDemangler) report (">>> name={}", name);

            return count > 0;
        }

        bool type ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("type");
            if (! input.length) return false;
            auto pos=checkpoint();
            switch (input[0])
            {
                case 'x':
                    consume (1);
                    output.append ("const ");
                    if (!type ()) return pos.reset();
                    return true;

                case 'y':
                    consume (1);
                    output.append ("invariant ");
                    if (!type ()) return pos.reset();
                    return true;

                case 'A':
                    consume (1);
                    if (type ())
                    {
                        output.append ("[]");
                        return true;
                    }
                    return pos.reset();

                case 'G':
                    consume (1);
                    uint size;
                    if (! number (size))
                        return false;
                    if (type ()) {
                        output.append ("[" ~ ctfe_i2a(size) ~ "]");
                        return true;
                    }
                    return pos.reset();

                case 'H':
                    consume (1);
                    auto pos2=checkpoint();
                    if (! type ())
                        return false;
                    char[] keytype=pos2.sliceFrom();
                    output.append ("[");
                    auto pos3=checkpoint();
                    if (type ())
                    {
                        char[]subtype=pos3.sliceFrom();
                        output.append ("]");
                        if (subtype.length<=keytype.length){
                            auto pos4=checkpoint();
                            output.append (keytype);
                            memmove(&output.data[pos2.len],&output.data[pos3.len],subtype.length);
                            output.data[pos2.len+keytype.length]='[';
                            memcpy(&output.data[pos2.len],&output.data[pos4.len],keytype.length);
                            pos4.reset();
                        }
                        return true;
                    }
                    return pos.reset();

                case 'P':
                    consume (1);
                    if (type ())
                    {
                        output.append ("*");
                        return true;
                    }
                    return false;
                case 'F': case 'U': case 'W': case 'V': case 'R': case 'D': case 'M':
                    return typeFunction ();
                case 'I': case 'C': case 'S': case 'E': case 'T':
                    return typeNamed ();
                case 'n':
                    consume (1);
                    output.append ("none");
                    return true;
                case 'v':
                    consume (1);
                    output.append ("void");
                    return true;
                case 'g':
                    consume (1);
                    output.append ("byte");
                    return true;
                case 'h':
                    consume (1);
                    output.append ("ubyte");
                    return true;
                case 's':
                    consume (1);
                    output.append ("short");
                    return true;
                case 't':
                    consume (1);
                    output.append ("ushort");
                    return true;
                case 'i':
                    consume (1);
                    output.append ("int");
                    return true;
                case 'k':
                    consume (1);
                    output.append ("uint");
                    return true;
                case 'l':
                    consume (1);
                    output.append ("long");
                    return true;
                case 'm':
                    consume (1);
                    output.append ("ulong");
                    return true;
                case 'f':
                    consume (1);
                    output.append ("float");
                    return true;
                case 'd':
                    consume (1);
                    output.append ("double");
                    return true;
                case 'e':
                    consume (1);
                    output.append ("real");
                    return true;
                case 'q':
                    consume(1);
                    output.append ("cfloat");
                    return true;
                case 'r':
                    consume(1);
                    output.append ("cdouble");
                    return true;
                case 'c':
                    consume(1);
                    output.append ("creal");
                    return true;
                case 'o':
                    consume(1);
                    output.append ("ifloat");
                    return true;
                case 'p':
                    consume(1);
                    output.append ("idouble");
                    return true;
                case 'j':
                    consume(1);
                    output.append ("ireal");
                    return true;
                case 'b':
                    consume (1);
                    output.append ("bool");
                    return true;
                case 'a':
                    consume (1);
                    output.append ("char");
                    return true;
                case 'u':
                    consume (1);
                    output.append ("wchar");
                    return true;
                case 'w':
                    consume (1);
                    output.append ("dchar");
                    return true;
                case 'B':
                    consume (1);
                    uint count;
                    if (! number (count))
                        return pos.reset();
                    output.append ('(');
                    if (! arguments ())
                        return pos.reset();
                    output.append (')');
                    return true;

                default:
                    return pos.reset();
            }

            return true;
        }

        bool typeFunction ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("typeFunction");
            
            auto pos=checkpoint();
            bool isMethod = false;
            bool isDelegate = false;

            if (input.length == 0)
                return false;

            if (input[0] == 'M')
            {
                consume (1);
                isMethod = true;
            }
            if (input[0] == 'D')
            {
                consume (1);
                isDelegate = true;
                assert (! isMethod);
            }

            switch (input[0])
            {
                case 'F':
                    consume (1);
                    break;

                case 'U':
                    consume (1);
                    output.append ("extern(C) ");
                    break;

                case 'W':
                    consume (1);
                    output.append ("extern(Windows) ");
                    break;

                case 'V':
                    consume (1);
                    output.append ("extern(Pascal) ");
                    break;

                case 'R':
                    consume (1);
                    output.append ("extern(C++) ");
                    break;

                default:
                    return pos.reset();
            }
            
            auto pos2=checkpoint();
            if (isMethod)
                output.append (" method (");
            else if (isDelegate)
                output.append (" delegate (");
            else
                output.append (" function (");
            
            arguments ();

            switch (input[0])
            {
                case 'X': case 'Y': case 'Z':
                    consume (1);
                    break;
                default:
                    return pos.reset();
            }
            output.append (")");
            
            auto pos3=checkpoint();
            if (! type ())
                return pos.reset();
            char[] retT=pos3.sliceFrom();
            auto pos4=checkpoint();
            output.append(retT);
            memmove(&output.data[pos2.len+retT.length],&output.data[pos2.len],pos3.len-pos2.len+1);
            memcpy(&output.data[pos2.len],&output.data[pos4.len],retT.length);
            pos4.reset();
            return true;
        }

        bool arguments ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("arguments");

            if (! argument ())
                return false;

            auto pos=checkpoint();
            output.append (", ");
            if (!arguments ()){
                pos.reset;
            }

            return true;
        }

        bool argument ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("argument");

            if (input.length == 0)
                return false;
            auto pos=checkpoint();
            switch (input[0])
            {
                case 'K':
                    consume (1);
                    output.append ("inout ");
                    break;

                case 'J':
                    consume (1);
                    output.append ("out ");
                    break;

                case 'L':
                    consume (1);
                    output.append ("lazy ");
                    break;

                default:
            }

            if (! type ())
                return pos.reset();

            return true;
        }

        bool typeNamed ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("typeNamed");
            auto pos=checkpoint();
            char[] kind;
            switch (input[0])
            {
                case 'I':
                    consume (1);
                    kind = "interface";
                    break;

                case 'S':
                    consume (1);
                    kind = "struct";
                    break;

                case 'C':
                    consume (1);
                    kind = "class";
                    break;

                case 'E':
                    consume (1);
                    kind = "enum";
                    break;

                case 'T':
                    consume (1);
                    kind = "typedef";
                    break;

                default:
                    return false;
            }

            //output.append (kind);
            //output.append ("=");

            if (! qualifiedName ())
                return pos.reset();

            if (prefs. printTypeKind)
            {
                output.append ("<");
                output.append (kind);
                output.append (">");
            }

            return true;
        }

        bool templateInstanceName ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("templateInstanceName");
            auto pos=checkpoint();
            if (input.length < 4 || input[0..3] != "__T")
                return false;

            consume (3);

            if (! lName ())
                return checkpoint.reset();

            output.append ("!(");

            _templateDepth++;
            if (_templateDepth <= prefs.templateExpansionDepth) {
                templateArgs ();
            } else {
                auto pos2=checkpoint();
                templateArgs ();
                pos2.resetOutput();
                output.append ("...");
            }
            _templateDepth--;

            if (input.length > 0 && input[0] != 'Z')
                return pos.reset();

            output.append (")");

            consume (1);
            return true;
        }

        bool templateArgs ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("templateArgs");

            if (! templateArg ())
                return false;
            auto pos1=checkpoint();
            output.append (", ");
            if (! templateArgs ())
            {
                pos1.reset();
            }

            return true;
        }

        bool templateArg ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("templateArg");

            if (input.length == 0)
                return false;
            auto pos=checkpoint();
            switch (input[0])
            {
                case 'T':
                    consume (1);
                    if (! type ())
                        return pos.reset();
                    return true;

                case 'V':
                    consume (1);
                    auto pos2=checkpoint();
                    if (! type ())
                        return pos.reset();
                    pos2.resetOutput();
                    if (! value ())
                        return pos.reset();
                    return true;

                case 'S':
                    consume (1);
                    if (! qualifiedName (true))
                        return pos.reset();
                    return true;

                default:
                    return pos.reset();
            }

            return pos.reset;
        }

        bool value ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("value");

            if (input.length == 0)
                return false;

            auto pos=checkpoint();

            switch (input[0])
            {
                case 'n':
                    consume (1);
                    return true;

                case 'N':
                    consume (1);
                    output.append ('-');
                    if (! numberNoParse ())
                        return pos.reset();
                    return true;

                case 'e':
                    consume (1);
                    if (! hexFloat ())
                        return pos.reset();
                    return true;

                case 'c': //TODO

                case 'A':
                    consume (1);
                    uint count;
                    if (! number (count))
                        return pos.reset();
                    if (count>0) {
                        output.append ("[");
                        for (uint i = 0; i < count-1; i++)
                        {
                            if (! value ())
                                return pos.reset();
                            output.append (", ");
                        }
                        if (! value ())
                            return pos.reset();
                    }
                    output.append ("]");
                    return true;

                default:
                    if (! numberNoParse ())
                        return pos.reset();
                    return true;
            }

            return pos.reset();
        }

        bool hexFloat ()
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("hexFloat");

            auto pos=checkpoint();
            if (input[0 .. 3] == "NAN")
            {
                consume (3);
                output.append ("nan");
                return true;
            }
            else if (input[0 .. 3] == "INF")
            {
                consume (3);
                output.append ("+inf");
                return true;
            }
            else if (input[0 .. 3] == "NINF")
            {
                consume (3);
                output.append ("-inf");
                return true;
            }

            bool negative = false;
            if (input[0] == 'N')
            {
                consume (1);
                negative = true;
            }

            ulong num;
            if (! hexNumber (num))
                return false;

            if (input[0] != 'P')
                return false;
            consume (1);

            bool negative_exponent = false;
            if (input[0] == 'N')
            {
                consume (1);
                negative_exponent = true;
            }

            uint exponent;
            if (! number (exponent))
                return pos.reset();

            return true;
        }

        static bool isHexDigit (char c)
        {
            return (c > '0' && c <'9') || (c > 'a' && c < 'f') || (c > 'A' && c < 'F');
        }

        bool hexNumber (ref ulong value)
        out (result)
        {
            debug(traceDemangler) trace (result);
        }
        body
        {
            debug(traceDemangler) trace ("hexFloat");

            if (isHexDigit (input[0]))
            {
                while (isHexDigit (input[0]))
                {
                    //output.append (input[0]);
                    consume (1);
                }
                return true;
            }
            else
                return false;
        }
    }
}


private struct Buffer
{
    char[] data;
    size_t     length;

    void append (char[] s)
    {
        assert(this.length+s.length<=data.length);
        size_t len=this.length+s.length;
        if (len>data.length) len=data.length;
        data[this.length .. len] = s[0..len-this.length];
        this.length = len;
    }

    void append (char c)
    {
        assert(this.length<data.length);
        data[this.length .. this.length + 1] = c;
        this.length += 1;
    }

    void append (Buffer b)
    {
        append (b.slice);
    }

    char[] slice ()
    {
        return data[0 .. this.length];
    }
}

/// the default demangler
static Demangler demangler;

static this(){
    demangler=new Demangler(1);
}
