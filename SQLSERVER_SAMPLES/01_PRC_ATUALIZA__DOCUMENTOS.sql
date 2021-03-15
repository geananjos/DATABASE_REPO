IF EXISTS(SELECT 1 FROM sys.procedures WHERE NAME = 'PRC_ATUALIZA_DOCUMENTOS')
  DROP PROCEDURE [dbo].[PRC_ATUALIZA_DOCUMENTOS]
GO
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE PROCEDURE [dbo].[PRC_ATUALIZA_DOCUMENTOS] 
  @p_result_id      NUMERIC,  
  @p_result_error   VARCHAR(4000) OUTPUT,
  @pi_s_cenario        VARCHAR(4000),
  @pi_n_empresa_fw     FLOAT
AS

--Variáveis de controle
DECLARE @v_seq_linha       FLOAT
DECLARE @v_verifica_cenario_existe  INT
DECLARE @v_contador_cenarios INT
DECLARE @v_contador_commit INT
DECLARE @v_mensagem_sucesso VARCHAR(MAX)
DECLARE @v_contador_colunas INT
DECLARE @v_msg_erro VARCHAR(MAX)

--Variáveis para o cursor
DECLARE
	@seq_linha NUMERIC,
	@codcenario VARCHAR(MAX),
	@estabelecimento VARCHAR(MAX), 
	@serie VARCHAR(MAX), 
	@num_doc_saida VARCHAR(MAX), 
	@codcliente VARCHAR(MAX), 
	@data_emissao VARCHAR(MAX),
	@natureza_operacao VARCHAR(MAX), 
	@cfop VARCHAR(MAX), 
	@num_due_pecex VARCHAR(MAX)

BEGIN
    SET @v_seq_linha = 0
	SET @v_contador_commit = 0
	
	--Verifica se cenário informado pela aplicação existe
	IF NOT EXISTS (SELECT COD_CENARIO FROM TBL_APPLICATION WHERE COD_CENARIO = @pi_s_cenario AND COD_EMPRESA_FW = @pi_n_empresa_fw)
	BEGIN
		SET @p_result_error = 'Cenário inexistente';
		EXEC dbo.PRC_ADD_ERROS @p_result_id, @p_result_error,'DOCS'
		SET @p_result_error = 'Erro no processamento.'
	END

	--Verifica se cenário informado no arquivo existe
	IF NOT EXISTS (SELECT cod_cenario FROM TBL_APPLICATION CEN WHERE CEN.COD_CENARIO IN 
					(SELECT TRIM(SUBSTRING(txt.DES_LINHA, 1, CHARINDEX(CHAR(59), txt.DES_LINHA, 1) - 1)) COD_CENARIO FROM TBL_APPLICATION_DADOS_TXT TXT WHERE COD_PROCESSO = @p_result_id AND @pi_n_empresa_fw = 1 AND SEQ_LINHA > 1 )
				  )
	BEGIN
		SET @p_result_error = 'Cenário inexistente';
		EXEC dbo.PRC_ADD_ERROS @p_result_id, @p_result_error,'DOCS'
		SET @p_result_error = 'Erro no processamento.'
	END

	--Verifica se existe mais de um cenário
	SET @v_contador_cenarios = (SELECT COUNT(DISTINCT(CENARIO.COD_CENARIO))
									FROM (SELECT TRIM(SUBSTRING(txt.DES_LINHA, 1, CHARINDEX(CHAR(59),txt.DES_LINHA, 1) - 1)) COD_CENARIO
													FROM TBL_APPLICATION_DADOS_TXT TXT
													WHERE COD_PROCESSO = @p_result_id AND  COD_EMPRESA_FW = @pi_n_empresa_fw AND   SEQ_LINHA > 1) AS CENARIO);
	IF @v_contador_cenarios > 1
	BEGIN 
		SET @p_result_error = 'Existe mais de um cenário no arquivo'
		EXEC dbo.PRC_ADD_ERROS @p_result_id, @p_result_error,'DOCS'
		SET @p_result_error = 'Erro no processamento.'
	END

	IF @p_result_error IS NULL
	BEGIN
		DECLARE C_TXT CURSOR FOR 
			SELECT SEQ_LINHA,
				dbo.FNC_GET_CSV_COLUMN(1, TXT.DES_LINHA, CHAR(59)) as COD_CENARIO,
				dbo.FNC_GET_CSV_COLUMN(2, TXT.DES_LINHA, CHAR(59)) as ESTABELECIMENTO,
				dbo.FNC_GET_CSV_COLUMN(3, TXT.DES_LINHA, CHAR(59)) as SERIE,
				dbo.FNC_GET_CSV_COLUMN(4, TXT.DES_LINHA, CHAR(59)) as NUM_DOC_SAIDA,
				dbo.FNC_GET_CSV_COLUMN(5, TXT.DES_LINHA, CHAR(59)) as COD_CLIENTE,
				dbo.FNC_GET_CSV_COLUMN(6, TXT.DES_LINHA, CHAR(59)) as DATA_EMISSAO,
				dbo.FNC_GET_CSV_COLUMN(7, TXT.DES_LINHA, CHAR(59)) as NATUREZA_OPERACAO,
				dbo.FNC_GET_CSV_COLUMN(8, TXT.DES_LINHA, CHAR(59)) as CFOP,
				dbo.FNC_GET_CSV_COLUMN(9, TXT.DES_LINHA, CHAR(59)) as NUM_DUE_PECEX
			FROM TBL_APPLICATION_DADOS_TXT TXT
			WHERE
			SEQ_LINHA > 1 AND COD_PROCESSO = @p_result_id AND  COD_EMPRESA_FW = @pi_n_empresa_fw;
      
	  OPEN C_TXT 

      FETCH next FROM C_TXT into @seq_linha, @codcenario, @estabelecimento, @serie, @num_doc_saida, @codcliente, @data_emissao, @natureza_operacao, @cfop, @num_due_pecex
	  
      WHILE @@FETCH_STATUS = 0 
        BEGIN
			
			--Verifica se o número de colunas está correto, através do caracter ';'
			SET @v_contador_colunas =  (SELECT LEN(txt.DES_LINHA) - LEN(REPLACE(txt.DES_LINHA, ';', ''))
											FROM TBL_APPLICATION_DADOS_TXT TXT 
												WHERE COD_PROCESSO = @p_result_id AND COD_EMPRESA_FW = @pi_n_empresa_fw AND SEQ_LINHA = @seq_linha )
			
			IF @v_contador_colunas > 8
			BEGIN
				SET @v_msg_erro = 'O arquivo possui o layout incorreto. Layout correto 9 colunas. Linha: ' + CAST(@seq_linha AS VARCHAR)
				EXEC dbo.PRC_ADD_ERROS @p_result_id, @v_msg_erro,'DOCS'
				SET @p_result_error = 'Erro no processamento.'
			END
			ELSE
			BEGIN
				IF @p_result_error IS NULL
				BEGIN
					BEGIN TRY
						UPDATE TBL_APPLICATION_DOCUMENTO
						SET NUM_DUE_PECEX = @num_due_pecex
						WHERE
							COD_CENARIO = @codcenario
							AND COD_ESTABEL = @estabelecimento
							AND SERIE = @serie
							AND NR_DOC_SAIDA = @num_doc_saida
							AND COD_CLIENTE = @codcliente
							AND CONVERT(DATE, DAT_EMIS_DOC, 103) = CONVERT(DATE, @data_emissao, 103)
							AND NAT_OPERACAO = @natureza_operacao
							AND CFOP = @cfop;

							SET @v_contador_commit = @v_contador_commit + 1;
					END TRY
					BEGIN CATCH
						SET @p_result_error = 'Erro na leitura do  arquivo na linha: ' + @seq_linha + CAST((SELECT ERROR_MESSAGE()) AS VARCHAR)
						EXEC dbo.PRC_ADD_ERROS @p_result_id, @p_result_error,'DOCS'
						SET @p_result_error = 'Erro no processamento.'
					END CATCH
				END -- END IF
			END --END ELSE
            
			FETCH next FROM C_TXT into @seq_linha, @codcenario, @estabelecimento, @serie, @num_doc_saida, @codcliente, @data_emissao, @natureza_operacao, @cfop, @num_due_pecex
			
        END --END WHILE
		CLOSE C_TXT;
		DEALLOCATE C_TXT;
		
		IF @v_contador_commit > 0
		BEGIN
			SET @v_mensagem_sucesso = 'Foram atualizados: '+ CONVERT(VARCHAR, @v_contador_commit) + ' documentos de saida.' 			
			EXEC dbo.PRC_ADD_MSG_SUCESSO @p_result_id, @v_mensagem_sucesso, 'DOCS', 0
			SET @p_result_error = ''
		END

		INSERT INTO TBL_APPLICATION_DADOS (COD_PROCESSO,SEQ_LINHA,DES_LINHA) VALUES (@p_result_id,@v_contador_commit,'UNIM;UN;UN;');
	END -- END IF BLOCO PRINCIPAL
END