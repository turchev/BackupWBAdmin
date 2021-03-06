<#
.SYNOPSIS
   Скрипт для резервного копирования, архивирования на сетевую папку и отправки сообщения
   о результате выполнения      
.DESCRIPTION
   Для резервного копирования используется утилита wbadmin. Реализация wbadmin в различных
   операциооных системах может отличаться (Windows 7 и 2008 отличаются от Windows 2008R2).
   На это следует обратить внимание при конфигурировании скрипта. Подробности по параметрам
   конфигурациооного файла и работе скрипта смотрите в файле ManBackupWBAdmin.txt
.PARAMETER -ConfigFile
   Конфигурациооный файл 
.EXAMPLE
   .\BackupWBAdmin.ps1 -ConfigFile C:\work\scripts\BackupWBAdmin\ConfigBackupWBAdmin.xml
.NOTES
   Вопросы и предложения пишите по адресу turchev@gmail.com
#>

#Region Parameters
param 
(
	# Обязательный параметр ConfigFile. Параметр пропускается через скрипт, 
	# который проверяет, существуют ли все элементы пути и если значение true, 
	# то продолжается работа
	[Parameter(mandatory=$true)]
	[ValidateScript({Test-Path $_ -PathType leaf})]
	[String]$ConfigFile		
)
#EndRegion

#Region Variables
####################################################
# Объявление переменных
####################################################

# Файл скрипта,выполняемого в данный момент
[IO.FileInfo]$ScriptName = $MyInvocation.MyCommand.Definition

# Директория, из которой исполнен скрипт
[string]$ScriptDirectoryName = $ScriptName.DirectoryName

# Директория для вспомогательных утилит
[string]$ToolsFolder = $ScriptDirectoryName, "Tools" -join "\"

# Директория для лог файлов
[string]$LogDirectoryName = $ScriptName.DirectoryName

# Лог файл
[IO.FileInfo] $LogName = `
	"$ScriptDirectoryName\logs\$($ScriptName.BaseName)\$($ScriptName.BaseName).$(get-date -format yyyy-MM-dd).log"

# Идентификатор загрузки конфигурационного файла
$CheckLoadXMLID = $false

# Объект с результирующей информацией
$JobResult = New-Object PSObject | Select-Object ComputerName,UserName,ScriptName,ConfigFile,LogFullName,Message
$JobResult.ComputerName = "$($env:computername)`n"
$JobResult.UserName = "$($env:username)`n"
$JobResult.ScriptName = "$($ScriptName.FullName)`n"
$JobResult.ConfigFile = "$ConfigFile`n"
$JobResult.LogFullName = "$($LogName.FullName)`n"

# Параметры для запуска утилиты WBadmin
[System.String]$wbInclude = $null
[System.String]$wbExclude = $null
[System.String]$wbBackupTarget = $null
[System.String]$wbTypeBackup = $null

######## Параметры для архивирования #########

# Идентификатор архивирования
[System.String]$ArchivingBackup = $null
# Директория WindowsImageBackup
[System.String]$WinImgBackFolder = $null
# Исполняемый файл архиватора 7z
[System.String]$script:name7z = $null
# Количество ротаций
[System.Byte]$CountRotation = $null
# Дни архивации
[System.String]$ArchivesDay = $null
# Дни ротации
[System.String]$RotationDay = $null
# Каталог для архивирования
[System.String]$ArchivesFolder = $null
# Размер сегмента архива в Гб
[System.Byte]$ArchiveSize = $null
# Пользователь для подключения ArchivesFolder
[System.String]$User = $null
# Пароль пользователя
[System.String]$Password = $null
# Имя диска для подключения
[System.String]$netDeviceName = $null

##############################################

#EndRegion

# XML Schema для валидации конфигурациооного файла
$XMLSchema =
 @"
 <xs:schema attributeFormDefault="unqualified" elementFormDefault="qualified" xmlns:xs="http://www.w3.org/2001/XMLSchema">
   <xs:element name="CONFIG">
     <xs:complexType>
       <xs:sequence>
	     
		 <xs:element name="BACKUPS">
           <xs:complexType>
             <xs:sequence>
               <xs:element type="xs:string" name="BackupTarget" minOccurs="1" maxOccurs="1"/>
               <xs:element type="xs:string" name="Include" minOccurs="0" maxOccurs="unbounded"/>
               <xs:element type="xs:string" name="Exclude" minOccurs="0" maxOccurs="unbounded"/>
               <xs:element type="xs:string" name="TypeBackup" minOccurs="0" maxOccurs="1"/>                              
             </xs:sequence>
           </xs:complexType>
         </xs:element>
		 
		 <xs:element name="ARCHIVE">
           <xs:complexType>
             <xs:sequence>
			   <xs:element type="xs:string" name="ArchivingBackup" minOccurs="1" maxOccurs="1"/> 
			   <xs:element type="xs:string" name="ArchivesDay" minOccurs="0" maxOccurs="1"/>
               <xs:element type="xs:string" name="CountRotation" minOccurs="0" maxOccurs="1"/>
			   <xs:element type="xs:string" name="RotationDay" minOccurs="0" maxOccurs="1"/>
               <xs:element type="xs:string" name="ArchivesFolder" minOccurs="0" maxOccurs="1"/>
			   <xs:element type="xs:string" name="ArchiveSize" minOccurs="0" maxOccurs="1"/>
               <xs:element type="xs:string" name="User" minOccurs="0" maxOccurs="1"/>
			   <xs:element type="xs:string" name="Password" minOccurs="0" maxOccurs="1"/>
             </xs:sequence>
           </xs:complexType>
         </xs:element>
		 
		 <xs:element name="SMTP">
           <xs:complexType>
             <xs:sequence>
			   <xs:element type="xs:string" name="SmtpMessage" minOccurs="1" maxOccurs="1"/>
               <xs:element type="xs:string" name="SmtpServerName" minOccurs="0" maxOccurs="1"/>
               <xs:element type="xs:integer" name="SmtpServerPort" minOccurs="0" maxOccurs="1"/>
               <xs:element type="xs:string" name="SmtpServerUsername" minOccurs="0" maxOccurs="1"/>
               <xs:element type="xs:string" name="SmtpServerPassword" minOccurs="0" maxOccurs="1"/>
               <xs:element type="xs:boolean" name="Ssl" minOccurs="0" maxOccurs="1"/>  
               <xs:element type="xs:string" name="Recipient" minOccurs="1" maxOccurs="unbounded"/>
               <xs:element type="xs:string" name="Sender" minOccurs="0" maxOccurs="1"/>			   
             </xs:sequence>
           </xs:complexType>
         </xs:element>
		        
	   </xs:sequence>
     </xs:complexType>
   </xs:element>
 </xs:schema>	
"@

#Region Functions
####################################################
# Функции
####################################################

#---------------------------------------------------
# Функция верификации и загрузки конфигурационного XML файла
#---------------------------------------------------
function Check-LoadXML() 
{	
	param 
	(
        [Parameter(Mandatory=$true)]
        [IO.FileInfo] $Path,
		
		[Parameter(Mandatory=$true)]
        [String] $Schema
    )
	
	Write-Verbose "Выполняется функция Check-LoadXML()"	
	
	$SchemaStringReader = New-Object System.IO.StringReader $XMLSchema
	$XmlReader = [System.Xml.XmlReader]::Create($SchemaStringReader)
		
    $settings = new-object System.Xml.XmlReaderSettings     
    $settings.ValidationType = [System.Xml.ValidationType]::Schema
    $settings.ValidationFlags = [System.Xml.Schema.XmlSchemaValidationFlags]::None
    $schemaSet = New-Object system.Xml.Schema.XmlSchemaSet;
    $settings.ValidationFlags = $settings.ValidationFlags -bor [System.Xml.Schema.XmlSchemaValidationFlags]::ProcessSchemaLocation

 	$schemaSet.Add($null, $XmlReader) | Out-Null
    $settings.Schemas = $schemaSet
 	
	# Обработчик события валидации. Сработает если конфигурационный файл не валиден
	$settings.add_ValidationEventHandler( {
      	$reader.Close()
		Write-Log -Message "XML файл не валиден. $($_.Message)" -Level "ERROR"		
		Finalize-Script		
    } )
 	
    $reader = [System.Xml.XmlReader]::Create($Path.FullName, $settings)

    try 
	{
        while($reader.Read()){}
        $reader.Close()
		Write-Log -Message "XML файл валиден"	
    }
    catch 
	{
        if (-not $reader.ReadState -eq "Closed") { $reader.Close() }
		$reader.Close()
		Write-Log -Message "XML файл имеет синтаксические ошибки. $($_.Message)" -Level "ERROR"
		return $false		
    }
	# Загрузка конфигурационных данных
	[XML] $script:Config = Get-Content $ConfigFile
	
	# Инициализация переменных с областью видимостии script
	$script:wbBackupTarget = $Config.CONFIG.BACKUPS.BackupTarget
	$script:wbTypeBackup = $Config.CONFIG.BACKUPS.TypeBackup
	$script:ArchivingBackup = $Config.CONFIG.ARCHIVE.ArchivingBackup
	$script:ArchivesFolder = $Config.CONFIG.ARCHIVE.ArchivesFolder
	$script:User = $Config.CONFIG.ARCHIVE.User
	$script:Password = $Config.CONFIG.ARCHIVE.Password
	
	return $true
}

#---------------------------------------------------
# Функция резервного копирования
#---------------------------------------------------
function WB-Backup() 
{

	Write-Verbose "Выполняется функция WB-Backup()"	
	
	# Проверка доступности пути, указанного в BackupTarget		
	if (-not $wbBackupTarget) 
	{
		Write-Log -Message "Параметр BackupTarget не может иметь значение NULL" -Level "Error"		
		return $false
	} 
	elseif (-not (Test-Path $wbBackupTarget)) 
	{		
		Write-Log -Message "Не найден путь $wbBackupTarget, заданный параметром BackupTarget " -Level "Error"
		return $false
	}
			
	# Формирование команды WBAdmin
   	[string]$private:WBAdminCommand = "wbadmin start backup"
	# добавляем в команду значение параметра -backupTarget
	$WBAdminCommand += " -backupTarget:`"$($wbBackupTarget)`""
	
	# Проверяем доступность пути, указанного в Include
	# и формируем строку для параметра Include команды wbAdmin		
	if ($Config.CONFIG.BACKUPS.Include) 
	{
		foreach ($iInclude in $Config.CONFIG.BACKUPS.Include) 
		{
    		if (-not (Test-Path $iInclude))
			{
		   		Write-Log -Message "Не найден путь $iInclude, заданный параметром Include " -Level "Error"				
				return $false
			} 
			else 
			{				
				[System.String]$script:wbInclude += "$iInclude,"
			}			
		}	
		$script:wbInclude = $wbInclude.Substring(0,($wbInclude.Length -1))
		# добавляем в команду значения параметра -include	
		$WBAdminCommand += " -include:`"$wbInclude`""	
	}
	
	# Проверка доступности пути, указанного в Exclude
	# и формируем строку для параметра Exclude команды wbAdmin
	if ($Config.CONFIG.BACKUPS.Exclude) 
	{
		foreach ($iExclude in $Config.CONFIG.BACKUPS.Exclude) 
		{
    		if (-not (Test-Path $iExclude))
			{
		   		Write-Log -Message "Не найден путь $iExclude, заданный параметром Exclude " -Level "Error"
				return $false
			} 
			else 
			{				
				[System.String]$script:wbExclude += "$iExclude,"
			} 	
		}
		$script:wbExclude = $wbExclude.Substring(0,($wbExclude.Length -1))
		# добавляем в команду значения параметра -exclude	
		$WBAdminCommand += " -exclude:`"$wbExclude`""	
	}
	
	# Проверка значения параметра TypeBackup, 
 	# может принимать значение systemState, allCritical или отсутствовать	
	if ($wbTypeBackup) 
	{
		if ($($wbTypeBackup) -ne "systemState") 
		{
			if ($($wbTypeBackup) -ne "allCritical") 			
			{	
				Write-Log -Message "Параметр TypeBackup имеет недопустимое значение $($wbTypeBackup)" -Level "Error"
				return $false				
			}			
		}
		# добавляем в команду параметр -allCritical или -systemState при их наличии
		$WBAdminCommand += " -$($wbTypeBackup)"
	}	
		
	# добавляем в команду параметр
	$WBAdminCommand += " -quiet"	
	
	### Запуск WBAdmin с параметрами в оболочке cmd.exe и поиском строк в выводе 
	
	# Массив искомых строк
	[string[]]$ArrSearchStr = @("Logs\WindowsServerBackup\Backup_Error","Logs\WindowsServerBackup\Backup-")	
	
	# Выполнение команды с возвратом результата, с выборкой последних 10 строк
	$CMDres = Invoke-Cmd -CommandString $WBAdminCommand -InSearchStr $ArrSearchStr -CountLastLines 10

	# Проверка на ошибки
	if ($CMDres.CmdErr)
	{
		Write-Log -Message "Wbadmin: $CMDres.CmdErr" -Level "Error"
		return $false
	} 

	Write-Log -Message "Вывод команды wbadmin (последнии 10 строк)" -Level "Info"	
	$CMDres.OutCmdRez | ForEach-Object { Write-Log -Message "Wbadmin: $_" -Level "Info" }
	
	###
			
	
	if ($ErrIdx) 
	{
		return $false
	}
	
	return $true	
}

#---------------------------------------------------
# Функция проверки готовности к архивированию
#---------------------------------------------------
function Check-BeforeArchiving(){	

	Write-Verbose "Выполняется функция Check-BeforeArchiving()"
	
	# Проверка значения параметра ArchivingBackup		
	if ( $ArchivingBackup -eq $false ) 
	{
		Write-Log -Message "Архивирование не запланировано" -Level "Info"
		return $false
	} 
	if ( $ArchivingBackup -ne $true ) 
	{
		Write-Log -Message "Параметр ArchivingBackup имеет недопустимое значение $ArchivingBackup" -Level "Error"
		return $false
	}
	
	# Проверка наличия 7Zip в папке Tools
	[System.String]$script:name7z = $ToolsFolder, "7za.exe" -join "\"
	if ( -not(Test-Path $name7z))
	{
		Write-log -Message "Отсутствует архиватор 7Zip в папке Tools" -Level "Error"			
		Return $False
	}
	
	# Инициализация переменной ArchivesDay 
	try 
	{
		$script:ArchivesDay = $Config.CONFIG.ARCHIVE.ArchivesDay
	} 
	catch 
	{
		Write-Log -Message "Параметр ArchivesDay имеет недопустимое значение $ArchivesDay" -Level "Error"
		return $false
	}
		
	# Инициализация переменной CountRotation, оно должно
	# соответствовать типу данных Byte 0-255
	try 
	{
		$script:CountRotation = $Config.CONFIG.ARCHIVE.CountRotation
	} 
	catch 
	{
		Write-Log -Message "Параметр CountRotation имеет недопустимое значение $CountRotation" -Level "Error"
		return $false
	}
	
	# Инициализация переменной RotationDay 
	try 
	{
		$script:RotationDay = $Config.CONFIG.ARCHIVE.RotationDay
	} 
	catch 
	{
		Write-Log -Message "Параметр RotationDay имеет недопустимое значение $RotationDay" -Level "Error"
		return $false
	}
	
	# Инициализация переменной ArchiveSize, оно должно
	# соответствовать типу данных Byte в диапазоне 0-255 
	try 
	{
		$script:ArchiveSize = $Config.CONFIG.ARCHIVE.ArchiveSize
	} 
	catch 
	{
		Write-Log -Message "Параметр ArchiveSize имеет недопустимое значение $CountRotation" -Level "Error"
		return $false
	}
	
	# Проверка наличия папки WindowsImageBackup в указанном BackupTarget
	[System.String]$script:WinImgBackFolder = $wbBackupTarget,"WindowsImageBackup" -join "\" # Директория WindowsImageBackup	
	if (-not (Test-Path $WinImgBackFolder))
	{
		Write-Log -Message "Не найден каталог WindowsImageBackup с резервными копиями " -Level "Error"
		return $false
	}	
		
	###### Монтирование каталога для архивирования	 

	$script:netDeviceName = "$(Get-FreePsDriveName)`:"
	
	# Формирование команды net use
   	[string]$NetUseCommand = "net use $netDeviceName `"$ArchivesFolder`"" 	
	if ($User) 
	{
		$NetUseCommand += " `/USER:$User"
	}	
	if ($Password) 
	{
		$NetUseCommand += " $Password"
	}
			
	### Запуск net use с параметрами в оболочке cmd.exe и обработкой вывода
	
	# Массив искомых строк (искомая строка одна, поэтому массив имеет один элемент)
	[string[]]$ArrSearchStr = @(,"Команда выполнена успешно")	
	
	# Выполнение команды с возвратом результата
	$CMDres = Invoke-Cmd -CommandString $NetUseCommand -InSearchStr $ArrSearchStr
	
	# Проверка на ошибки
	if ($CMDres.CmdErr)
	{
		Write-Log -Message "net use: $CMDres.CmdErr" -Level "Error"
		return $false
	} 		
	if (-not $CMDres.OutSearchFullStr[0]) 
	{
		Write-Log -Message "Ошибка команды net use" -Level "Error"
		return $false
	}
	
	Write-Log -Message "Вывод результата работы net use" -Level "Info"	
	$CMDres.OutCmdRez | ForEach-Object { Write-Log -Message "net use: $_" -Level "Info" }
	Write-Log -Message "net use: Диск $netDeviceName успешно подключен" -Level "Info"
	
	return $true
}

#---------------------------------------------------
# Функция ротации директории
#---------------------------------------------------
function Rotate-Dir() 
{
	Param 
	(			
		# Директория, в которой происходит ротация
		[Parameter(mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$in_RotationDir,		
		
		# Количество недель ротации
		[Parameter(mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[int]$in_CountRotation			
		
	)	 
	
	Write-Verbose "Выполняется функция Rotate-Dir()"
	
	# Проверка директории 
	if ( -not(Test-Path $in_RotationDir) )
	{
		Write-Log -Message "Не найдена директория $in_RotationDir" -Level "Error"
		return $false
	}	
	
	### Ротация
	$maxCountRotationDir = "$in_RotationDir\$in_CountRotation" 
	# Если имеется директория с максимальным номером, то удаляем ее
	if ( Test-Path $maxCountRotationDir ) 
	{
		Remove-Item $maxCountRotationDir -Confirm:$false -Force -Recurse -ErrorAction SilentlyContinue -ErrorVariable ErrLogDir | Out-Null
		# Информация для отладки и останов в случае отсутствия доступа к директории
		if ( $ErrLogDir ) 
		{					
			Write-Verbose "*ERROR* Ошибка удаления $ErrLogDir"
			return $false
		}
	}
	# Переименовываем каталоги со смещением на 1
	for ($i=$in_CountRotation-1;$i -ge 1; $i-=1)
	{
		if (Test-Path "$in_RotationDir\$i") 
		{
			Rename-Item -Path "$in_RotationDir\$i" -NewName "$($i+1)" -Confirm:$false -Force -ErrorAction SilentlyContinue -ErrorVariable ErrLogDir | Out-Null
			# Информация для отладки и останов в случае отсутствия доступа к директории
			if ( $ErrLogDir ) 
			{					
				Write-Verbose "*ERROR* Ошибка переименования $ErrLogDir"
				return $false
			}
		}
	}
	
	return $true
	
}

#---------------------------------------------------
# Функция архивирования
#---------------------------------------------------
function Start-Archiving() 
{

	Write-Verbose "Выполняется функция Start-Archiving()"
	
	# Директория для архивных копий (проверка/создание)
	$netFolderArhive = "$netDeviceName\1"		
	if ( -not(Test-Path $netFolderArhive ) ) 
	{
		New-Item $netFolderArhive -Type Directory -Confirm:$false -Force -ErrorAction SilentlyContinue -ErrorVariable ErrLogDir | Out-Null
		# Информация для отладки и останов в случае отсутствия доступа к директории
		if ( $ErrLogDir ) 
		{				
			Write-Verbose "*ERROR* Не удалось создать директорию $netFolderArhive"
			Write-Verbose "*ERROR* $ErrLogDir"
			return $false
		}
	}
	
	# Формирование команды 7-zip
   	[string]$str7zCommand = "$name7z a -t7z"
	
	# Разбиение архива на сегменты
	if ($ArchiveSize) 
	{
		$str7zCommand += " -v$($ArchiveSize)g"
	}

	# добавляем в команду имя архива
	$str7zCommand += " `"$netFolderArhive\$env:computername.$(get-date -format yyyy-MM-dd_HH-mm).7z`""
	
	# добавляем в команду исходный каталог 
	$str7zCommand += " `"$WinImgBackFolder`""
	
	### Запуск 7za.exe с параметрами в оболочке cmd.exe и обработкой вывода
	
	# Массив искомых строк (искомая строка одна, поэтому массив имеет один элемент)
	[string[]]$ArrSearchStr = @(,"Everything is Ok")	
	
	# Выполнение команды с возвратом результата
	$CMDres = Invoke-Cmd -CommandString $str7zCommand -InSearchStr $ArrSearchStr -CountLastLines 10
	
	# Проверка на ошибки
	if ($CMDres.CmdErr)
	{
		Write-Log -Message "7z: $CMDres.CmdErr" -Level "Error"
		return $false
	} 		
	if (-not $CMDres.OutSearchFullStr[0]) 
	{
		Write-Log -Message "Ошибка команды 7z" -Level "Error"
		return $false
	}
		
	Write-Log -Message "Вывод результата работы архиватора 7z (последнии 10 строк)" -Level "Info"	
	$CMDres.OutCmdRez | ForEach-Object { Write-Log -Message "7z: $_" -Level "Info" }
	
	return $true
}

#---------------------------------------------------
# Функция Send-Email()
#---------------------------------------------------
function Send-Email() 
{
	Param 
	(
		# Текст сообщения
		[Parameter(Mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		$Job
	)
	
	Write-Verbose "Выполняется функция Send-Email()"	
	
	$Subject = " ($($env:computername)) $($script:ScriptName.BaseName)"		
	$Body = $Job	
	$SMTPclient = new-object System.Net.Mail.SmtpClient $Config.CONFIG.SMTP.SmtpServerName
 
	# SMTP порт
	$SMTPClient.port = $Config.CONFIG.SMTP.SmtpServerPort
 
	# Использовать/Неиспользовать SSL
	if ( $Config.CONFIG.SMTP.Ssl -eq $true ) 
	{
		$SMTPclient.EnableSsl = $true
	}
 
	# Формирование и отправка почтовых сообщений
	if ( $Config.CONFIG.SMTP.SmtpServerUsername -and $Config.CONFIG.SMTP.SmtpServerPassword) 
	{
		$SMTPAuthUsername = $Config.CONFIG.SMTP.SmtpServerUsername
		$SMTPAuthPassword = $Config.CONFIG.SMTP.SmtpServerPassword
		$SMTPClient.Credentials = New-Object System.Net.NetworkCredential($SMTPAuthUsername, $SMTPAuthPassword)
 	} 
	try 
	{
        $MailMessage = new-object System.Net.Mail.MailMessage
        $MailMessage.From = $Config.CONFIG.SMTP.Sender
        $MailMessage.Subject = $Subject
        $MailMessage.Body = $Body 

		foreach ( $Recipient in $Config.CONFIG.SMTP.Recipient ) 
		{
            $MailMessage.To.Add($Recipient)			
			Write-log -Message "Отправка сообщения на адрес $Recipient"
        }

	    $SMTPclient.Send($MailMessage)        
    }
    catch 
	{
        Write-log -Message "Не удалось отправить почту: $($_.Exception.Message)" -Level Error
    }
}

#---------------------------------------------------
# Функция записи в лог файл
#---------------------------------------------------
function Write-Log 
{	
	Param 
	(	
		[Parameter(ValueFromPipeline=$true)]
		[string] $Message = "",
			
		# Путь к лог файлу. По умолчанию будет использован файл  во временном каталоге
		[Parameter()]
		[IO.FileInfo] $Path = $LogName,
			
		# Уровни информации
		[Parameter()] [ValidateSet("Error","Warning","Info")]
		[String] $Level = "Info"
	)	 
		
	Begin {}	
	
	Process 
	{
		#Проверка / Создание директории для лог файлов	
		if ( -not(Test-Path $Path.DirectoryName ) ) 
		{
			New-Item $Path.DirectoryName -Type Directory -Confirm:$false -Force -ErrorAction SilentlyContinue -ErrorVariable ErrLogDir | Out-Null
			# Информация для отладки и останов в случае отсутствия доступа к директории
			if ( $ErrLogDir ) 
			{				
				Write-Verbose "*ERROR* Не удалось создать директорию $($Path.DirectoryName)"
				Write-Verbose "*ERROR* $ErrLogDir"
				break
			}
		}
		# Создание файла и Запись сообщения в лог файл		
		$msg = '{0} *{1}*	{2}' -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level.ToUpper(), $Message
		Add-Content -Path $Path -Value $msg -ErrorAction SilentlyContinue -ErrorVariable ErrLogFile				
		# Информация для отладки и останов в случае отсутствия доступа к файлу
		if ( $ErrLogFile ) 
		{
			Write-Verbose "*ERROR* Не удалось записать в файл $Path"
			Write-Verbose "*ERROR* $ErrLogFile"
			break
		}				
		$JobResult.Message += "`n$msg"		
	}
	
	End {}
}
 
#---------------------------------------------------
# Функция запуска утилит в оболочке cmd.exe и обработки результата
#---------------------------------------------------
function Invoke-Cmd() 
{	
	Param 
	(	
		# Параметр типа string,
		# команда, выполняемая в cmd.exe
		[Parameter(mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$CommandString,		
		
		# Парамет типа массив string.
		# Искомые строки (каждая в отдельном элементе массива),будут отыскиваться в результате выполнения команды 
		[Parameter(mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string[]]$InSearchStr,			
		
		# Параметр количество последних строк вывода,
		# по умолчанию все строки, параметр не обязательный
		[Parameter()]	
		#[ValidateScript({$_ -gt 0})]
		[int]$CountLastLines
	)	 
	
	Write-Verbose "Выполняется функция Invoke-Cmd($CommandString)"
	
	###### возвращаемый	результат
		$ReturnResult = New-Object PSObject | Select-Object CmdErr,OutCmdRez,OutSearchFullStr
		# Строка ошибки, возвращаемая cmd.exe
		[string]$ReturnResult.CmdErr = ""
		# Результат выполнения команды, построчно, каждая строка - отдельный элемент массива
		[string[]]$ReturnResult.OutCmdRez = @()
		# Массив найденных строк, формируем его в размер массива-параметра функции, обнуляя
		[string[]]$ReturnResult.OutSearchFullStr = $InSearchStr[0..$($InSearchStr.Length-1)]
		for ($i=0;$i -le $ReturnResult.OutSearchFullStr.length-1;$i+=1)
		{
			$ReturnResult.OutSearchFullStr[$i] = $null
		}
	######

	# Запуск команды с параметрами в оболочке cmd.exe	 
	$CmdRez = Invoke-Command -ScriptBlock {param ($CmdParam, $Command) cmd.exe $CmdParam $Command} -ArgumentList "/C",$CommandString # 2>$null
	
	### Обработка возвращаемого результата
	
	# Если ошибка
	if (-not $($CmdRez)) 
	{	
		$Err0 = $Error[0].Exception.Message
		$Err1 = $Error[1].Exception.Message	
		$ReturnResult.CmdErr = "$Err1 $Err0"
		return $ReturnResult
	} 	
	
	# Проходим построчно результат вывода, выводим количество строк указанных в параметре CountLastLines, 
	# ищем вхождения искомых строк,
	if ($CountLastLines)
	{
		$CountLastLines = $CmdRez.Length-$CountLastLines
	} 	
	for ($j=0;$j -le $CmdRez.Length-1;$j+=1)
	{		
		if ($j -ge $CountLastLines)
		{
			$ReturnResult.OutCmdRez += $CmdRez[$j]
		}
		for ($i=0;$i -le $InSearchStr.length-1;$i+=1) 
		{
			$IndexFindStr = $CmdRez[$j].IndexOf($InSearchStr[$i])			
			if ($IndexFindStr -ne "-1") 
			{
				$ReturnResult.OutSearchFullStr[$i] = $CmdRez[$j]
				break
			}
		}				
	}
	
	return $ReturnResult	
#	
#	# Пример использования	
#	$cmdline = "ipconfig /all"
#	[string[]]$arr = @()
#	$arr += "Физический адрес"
#	$arr += "Имя компьютера"
#	$arr += "IPv4-адрес"
#
#	$rexxx = Invoke-Cmd -CommandString $cmdline -InSearchStr $arr

}
	
#---------------------------------------------------
# Функция сравнивает параметры с номером дня недели
#---------------------------------------------------
function Compare-CurrentDate()
{
	Param 
	(
		[Parameter(mandatory=$true)]
		[ValidateNotNullOrEmpty()]
		[string]$strCompareDay		
	)

	Write-Verbose "Выполняется функция Compare-CurrentDate()"
	
	$idx = $false
	
	# Текущая дата
	$CurrentDate = Get-Date		
	
	[string[]]$arrStrCompareDay = $strCompareDay.Split(",")
	try
	{
		[int[]]$arrIntCompareDay = $arrStrCompareDay
	}
	catch
	{
		Write-Log -Message "Некорректный параметр функции Compare-CurrentDate()" -Level "Error"
		Finalize-Script		
	}
	
	foreach ($intElement in $arrIntCompareDay)
	{
		if (($intElement -lt 0) -or ($intElement -gt 6))
		{
			Write-Log -Message "Параметр $intElement функции Compare-CurrentDate() вне диапазона 1-7" -Level "Error"
			Finalize-Script
		}
		if ($intElement -eq $CurrentDate.DayOfWeek.value__)
		{	
			Write-Log -Message "Элементы равны" -Level "Info"
			$idx = $true
		}
	}
	
	return $idx
	
}


#---------------------------------------------------
# Функция выбора свободной буквы диска
#---------------------------------------------------
function Get-FreePsDriveName() 
{
	
	Write-Verbose "Выполняется функция Get-FreePsDriveName()"
	
	# Объект Devicelist для определения уже подключенных дисков 	
	$Devicelist = get-psdrive -psprovider filesystem
	
	# Набор букв для выбора
	$CharList = @("C","D","E","F","G","H","I","J","K","L","M","N","O","P","Q","R","S","T","U","V","W","X","Y","Z")	
	# Выбор свободной буквы диска
	foreach($iChar in $CharList)
	{
		$idx = $true
		foreach ($iDevice in $Devicelist)
		{
			if ($iDevice.name -eq $iChar)
			{
				$idx = $false
				break
			}			
		}
		if ($idx) 
		{
			return "$iChar"		
		}	
	}	
	
}

#---------------------------------------------------
# Функция генерации отчета с последующим завершением скрипта
#---------------------------------------------------
Function Finalize-Script() 
{ 
	
	Write-Verbose "Выполняется функция Finalize-Script()"
	
	# Размонтирование каталога для архивирования
	if ($netDeviceName) 
	{
		# Формирование команды net use /DELETE
   		[string]$NetUseCommand = "net use $netDeviceName `/DELETE /YES" 	
		# Массив искомых строк (искомая строка одна, поэтому массив имеет один элемент)
		[string[]]$ArrSearchStr = @(,"успешно удален")		
		# Выполнение команды с возвратом результата
		$CMDres = Invoke-Cmd -CommandString $NetUseCommand -InSearchStr $ArrSearchStr
		# Проверка на ошибки
		if ($CMDres.CmdErr)
		{
			Write-Log -Message "net use: $CMDres.CmdErr" -Level "Error"		
		} 		
		if (-not $CMDres.OutSearchFullStr[0]) 
		{
			Write-Log -Message "Ошибка команды net use" -Level "Error"		
		}	
		Write-Log -Message "Вывод результата работы net use" -Level "Info"	
		$CMDres.OutCmdRez | ForEach-Object { Write-Log -Message "net use: $_" -Level "Info" }
	}
	
	if ( -not $CheckLoadXMLID ) 
	{
		Write-Log -Message "Нет конфигурационных данных для отправки сообщения" -Level "Error"
		Write-Log -Message "Сообщение не отправлено" -Level "Error"
	} 
	elseif ($Config.CONFIG.SMTP.SmtpMessage -ne $true) 
	{
		Write-Log -Message "Сообщение не будет отправлено" -Level "Info"
	} 
	else 
	{
		Send-Email $JobResult
	}		
	Write-Log -Message "----------------- Script end -----------------`n" -Level "Info"		
	Write-Verbose $JobResult.Message
	Write-Debug $JobResult
	
	Exit
}
	
#EndRegion

 
####################################################
# Main
####################################################

#Region Main
Write-Log -Message "---------------- Script start ----------------" -Level "Info"

# Верификация и загрузка конфигурационного XML файла
if (-not(Check-LoadXML -Path $ConfigFile -Schema $XMLSchema)) 
{
	Write-Log -Message "Конфигурацонный файл не загружен" -Level "Error"
	Finalize-Script
}
Write-Log -Message "Конфигурационный файл загружен" -Level "Info"
$CheckLoadXMLID = $true	

# Выполнение резервного копирования
if (-not (WB-Backup)) 
{
	  Write-Log -Message "Ошибка резервирования" -Level "Error"	
	  Finalize-Script
} 
Write-Log -Message "Резервирование завершилось успешно" -Level "Info"

# Проверка конфигурационных данных для архивирования
if (-not(Check-BeforeArchiving)) 
{
	Write-Log -Message "Проверка готовности к архивированию не пройдена" -Level "Error"	
	Finalize-Script
} 
Write-Log -Message "Проверка готовности к архивированию пройдена" -Level "Info"

# Если текущий день недели совпадает с днем ротации, выполняем ротацию
if ( Compare-CurrentDate -strCompareDay $RotationDay )
{
	if ( -not (Rotate-Dir -in_RotationDir $netDeviceName -in_CountRotation $CountRotation) )
	{
		$RotationDay	
		Finalize-Script
	} 
	Write-Log -Message "Ротация выполнена" -Level "Info"
}
else
{
	Write-Log -Message "Ротация не запланирована" -Level "Info"
}

# Если текущий день недели совпадает с днем архивации, то выполняем архивирование
if ( Compare-CurrentDate -strCompareDay $ArchivesDay )
{
	if (-not (Start-Archiving)) 
	{
		Write-Log -Message "Ошибка архивирования" -Level "Error"	
		Finalize-Script	
	}
	Write-Log -Message "Архивирование завершилось успешно" -Level "Info"
}	
else
{
	Write-Log -Message "Архивирование не запланировано" -Level "Info"
}

Finalize-Script

#EndRegion