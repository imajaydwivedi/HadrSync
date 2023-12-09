use master
go
IF OBJECT_ID('master.dbo.Get_HASH_val_for_Large_String') is null
	exec ('create function dbo.Get_HASH_val_for_Large_String () returns varbinary(200) as begin return null end;')
go
alter FUNCTION [dbo].[Get_HASH_val_for_Large_String]
(
    @St_val nvarchar(max)
)

RETURNS varbinary(200)

AS
BEGIN

    Declare @Int_Len as integer
    Declare @varBina_Val as varbinary(20)
    Declare @Max_len int  = 3999

    Set @Int_Len = len(@St_val)

    if @Int_Len > @Max_len

			Begin
        ;With
            hashbytes_val
            as
            (
                                    Select substring(@St_val,1, @Max_len) val, @Max_len+1 as st, @Max_len lv,
                        hashbytes('SHA2_256', substring(@St_val,1, @Max_len)) hashval
                Union All
                    Select substring(@St_val,st,lv), st+lv , @Max_len  lv,
                        hashbytes('SHA2_256', substring(@St_val,st,lv) + convert( varchar(20), hashval ))
                    From hashbytes_val
                    where Len(substring(@St_val,st,lv))>0
            )
        Select @varBina_Val = (Select Top 1
                hashval
            From hashbytes_val
            Order by st desc)
        return @varBina_Val
    End
	else
    Begin
        Set @varBina_Val = hashbytes('SHA2_256', @St_val)
        return @varBina_Val
    End
    return NULL
END
go