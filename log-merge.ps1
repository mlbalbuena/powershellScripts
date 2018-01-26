<#  
.SYNOPSIS  

    powershell script to merge multiple csv files with timestamps by timestamp into new file

.DESCRIPTION  
    powershell script to merge multiple csv files with timestamps by timestamp into new file

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

.NOTES  
   File Name  : log-merge.ps1  
   Author     : jagilber
   Version    : 171106 prependfilename virtual date

   History    : 
                160619 added "o" date format

.EXAMPLE  

    .\log-merge.ps1 -sourceFolder c:\logfiles -filePattern *evt*.csv -outputFile c:\temp\all-events.csv
    Search c:\logfiles folder for all files matching pattern *evt*.csv and output to c:\temp\all-events.csv   

.EXAMPLE  

    .\log-merge.ps1 -sourceFolder c:\logfiles -filePattern *FMT*.csv -outputFile c:\temp\all-etw.csv
    Search c:\logfiles folder for all files matching pattern *FMT*.txt and output to c:\temp\all-etw.csv   

.PARAMETER sourceFolder
    Path to source folder to be searched. ex: c:\logfiles

.PARAMETER filePattern
    Dos style file matching pattern for csv files to parse. ex: *evt*.csv

.PARAMETER outputFile
    Name and location of the new merged file. ex: c:\temp\test.csv

.PARAMETER startDate
    optional parameter to exclude lines with dates older than given date

.PARAMETER endDate
    optional parameter to exclude lines with dates newer than given date
#>  

Param(
 
    [parameter(Position = 0, Mandatory = $true, HelpMessage = "Enter the source folder for searching:")]
    [string] $sourceFolder,
    [parameter(Position = 1, Mandatory = $true, HelpMessage = "Enter the file filter pattern (dos style *.*):")]
    [string] $filePattern,
    [parameter(Position = 2, Mandatory = $true, HelpMessage = "Enter the new file name:")]
    [string] $outputFile = "log-merge.csv",
    [parameter(Position = 3, Mandatory = $false, HelpMessage = "Use to enable subdir search")]
    [switch] $subDir,
    [string] $startDate,
    [string] $endDate,
    [bool]$prependFileName = $true
)



$Code = @'
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.IO;
using System.Text.RegularExpressions;
using System.Globalization;


public class LogMerge
{
    private CultureInfo culture = new CultureInfo("en-US");
    private string dateFormatDefault = "yyyy-MM-dd HH:mm:ss.fffffff";
    private string dateFormatAzure = "yyyy-MM-dd HH:mm:ss.fff";
    private string dateFormatEtl = "MM/dd/yyyy-HH:mm:ss.fff";
    private string dateFormatEtlPrecise = "MM/dd/yy-HH:mm:ss.fffffff";
    private string dateFormatEvt = "MM/dd/yyyy,hh:mm:ss tt";
    private string dateFormatEvtPrecise = "MM/dd/yyyy,hh:mm:ss.ffffff tt";
    private string dateFormatEvtSpace = "MM/dd/yyyy hh:mm:ss tt";
    private string dateFormatISO = "yyyy-MM-ddTHH:mm:ss.ffffff";

    //07/22/2014-14:48:10.909 for etl and 07/22/2014,14:48:10 PM for eventlog
    private string datePattern = "(?<DateEtlPrecise>[0-9]{1,2}/[0-9]{1,2}/[0-9]{2,4}-[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\\.[0-9]{7}) |" +
        "(?<DateEtl>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4}-[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\\.[0-9]{3}) |" +
        "(?<DateEvt>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4},[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2} [AP]M)|" +
        "(?<DateEvtSpace>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4} [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2} [AP]M)|" +
        "(?<DateEvtPrecise>[0-9]{1,2}/[0-9]{1,2}/[0-9]{4},[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\\.[0-9]{6} [AP]M)|" +
        "(?<DateISO>[0-9]{4}-[0-9]{1,2}-[0-9]{1,2}T[0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\\.[0-9]{3,7})|" +
        "(?<DateAzure>[0-9]{4}-[0-9]{1,2}-[0-9]{1,2} [0-9]{1,2}:[0-9]{1,2}:[0-9]{1,2}\\.[0-9]{3,7})";

    // may have additional digits and Z
    private bool detail = false;

    private Int64 missedDateCounter = 0;
    private Int64 missedMatchCounter = 0;
    private Dictionary<string, string> outputList = new Dictionary<string, string>();
    private int precision = 0;

    public static void Start(string sourceFolder, string filePattern, string outputFile, string defaultDir, bool subDir, DateTime startDate, DateTime endDate, bool prependFileName)
    {
        LogMerge program = new LogMerge();

        try
        {
            Directory.SetCurrentDirectory(defaultDir);

            if (!string.IsNullOrEmpty(sourceFolder) && !string.IsNullOrEmpty(filePattern) && !string.IsNullOrEmpty(outputFile))
            {
                SearchOption option;

                if (subDir)
                {
                    option = SearchOption.AllDirectories;
                }
                else
                {
                    option = SearchOption.TopDirectoryOnly;
                }

                string[] files = Directory.GetFiles(sourceFolder, filePattern, option);
                if (files.Length < 1)
                {
                    Console.WriteLine("unable to find files. returning");
                    return;
                }

                program.ReadFiles(files, outputFile, startDate, endDate, prependFileName);
            }
            else
            {
                Console.WriteLine("utility combines *fmt.txt files into one file based on timestamp. provide folder and filter args and output file.");
                Console.WriteLine("LogMerge takes three arguments; source dir, file filter, and output file.");
                Console.WriteLine("example: LogMerge f:\\cases *fmt.txt c:\\temp\\all.csv");
            }
        }
        catch (Exception e)
        {
            Console.WriteLine(string.Format("exception:main:precision:{0}:missed:{1}:excetion:{2}", program.precision, program.missedMatchCounter, e));
        }
    }

    private bool AddToList(DateTime date, string line)
    {
        string key = string.Format("{0}{1}", date.Ticks.ToString(), precision.ToString("D8"));
        if (!outputList.ContainsKey(key))
        {
            outputList.Add(key, line);
        }
        else
        {
            return false;
        }

        return true;
    }

    public bool ReadFiles(string[] files, string outputfile, DateTime startDate, DateTime endDate, bool prependFileName)
    {
        try
        {
            foreach (string file in files)
            {
                Console.WriteLine(file);
                string fileName = Path.GetFileName(file);
                string line = string.Empty;
                DateTime refDate = new DateTime();
                StreamReader reader = new StreamReader(file);

                while (reader.Peek() >= 0)
                {
                    line = ParseLine(reader.ReadLine(), ref refDate);

                    if (!(startDate < refDate && refDate < endDate))
                    {
                        continue;
                    }

                    if (prependFileName)
                    {
                        line = string.Format("{0}, {1}", fileName, line);
                    }

                    while (precision < 99999999)
                    {
                        if (AddToList(refDate, line))
                        {
                            break;
                        }

                        precision++;
                    }
                }
            }

            if (File.Exists(outputfile))
            {
                File.Delete(outputfile);
            }

            using (StreamWriter writer = new StreamWriter(outputfile, true))
            {
                Console.WriteLine("sorting lines.");
                foreach (var item in outputList.OrderBy(i => i.Key))
                {
                    writer.WriteLine(item.Value);
                }
            }

            Console.WriteLine(string.Format("finished:missed {0} lines", missedMatchCounter));
            return true;
        }
        catch (Exception e)
        {
            Console.WriteLine(string.Format("ReadFiles:exception: dictionary count:{1}: exception:{2}", outputList.Count, e));
            return false;
        }
    }

    public string ParseLine(string line, ref DateTime refDate)
    {
        Match match = Match.Empty;
        long lastTicks = refDate.Ticks + 1;
        string lastPidString = string.Empty;
        string traceDate = string.Empty;
        string dateFormat = dateFormatDefault;
        string pidPattern = "^(.*)::";

        if (Regex.IsMatch(line, pidPattern))
        {
            lastPidString = Regex.Match(line, pidPattern).Value;
        }

        Match matchTraceDate = Regex.Match(line, datePattern);

        if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateEtlPrecise"].Value))
        {
            dateFormat = dateFormatEtlPrecise;
            traceDate = matchTraceDate.Groups["DateEtlPrecise"].Value;
        }
        else if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateEtl"].Value))
        {
            dateFormat = dateFormatEtl;
            traceDate = matchTraceDate.Groups["DateEtl"].Value;
        }
        else if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateEvt"].Value))
        {
            dateFormat = dateFormatEvt;
            traceDate = matchTraceDate.Groups["DateEvt"].Value;
        }
        else if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateEvtSpace"].Value))
        {
            dateFormat = dateFormatEvtSpace;
            traceDate = matchTraceDate.Groups["DateEvtSpace"].Value;
        }
        else if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateEvtPrecise"].Value))
        {
            dateFormat = dateFormatEvtPrecise;
            traceDate = matchTraceDate.Groups["DateEvtPrecise"].Value;
        }
        else if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateISO"].Value))
        {
            dateFormat = dateFormatISO;
            traceDate = matchTraceDate.Groups["DateISO"].Value;
        }
        else if (!string.IsNullOrEmpty(matchTraceDate.Groups["DateAzure"].Value))
        {
            dateFormat = dateFormatAzure;
            traceDate = matchTraceDate.Groups["DateAzure"].Value;
        }
        else
        {
            if (detail) Console.WriteLine("unable to parse date:{0}:{1}", missedDateCounter, line);
            missedDateCounter++;
        }

        if (DateTime.TryParseExact(traceDate,
            dateFormat,
            culture,
            DateTimeStyles.AssumeLocal,
            out refDate))
        {
            if (lastTicks != refDate.Ticks)
            {
                lastTicks = refDate.Ticks;
                precision = 0;
            }
        }
        else if (DateTime.TryParse(traceDate, out refDate))
        {
            if (lastTicks != refDate.Ticks)
            {
                lastTicks = refDate.Ticks;
                precision = 0;
            }

            dateFormat = dateFormatEvt;
        }
        else
        {
            // use last date and let it increment to keep in place
            refDate = new DateTime(lastTicks);

            // put cpu pid and tid back in

            if (Regex.IsMatch(line, pidPattern))
            {
                line = string.Format("{0}::{1}", lastPidString, line);
            }
            else
            {
                line = string.Format("{0}{1} -> {2}", lastPidString, refDate.ToString(dateFormat), line);
            }

            missedMatchCounter++;
            Console.WriteLine("unable to parse time:{0}:{1}", missedMatchCounter, line);
        }

        return line;
    }
}
'@

Add-Type $Code

[DateTime] $time = new-object DateTime

if (![DateTime]::TryParse($startDate, [ref] $time))
{
    $startDate = [DateTime]::MinValue
}

if (![DateTime]::TryParse($endDate, [ref] $time))
{
    $endDate = [DateTime]::MaxValue
}

[LogMerge]::Start($sourceFolder, $filePattern, $outputFile, (get-location), $subDir, $startDate, $endDate, $prependFileName)


