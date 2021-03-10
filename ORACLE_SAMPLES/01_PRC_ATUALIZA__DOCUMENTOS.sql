CREATE OR REPLACE NONEDITIONABLE PROCEDURE PRC_ATUALIZA_DOCUMENTOS
   (p_result_id     IN  NUMBER,
    p_result_error  OUT VARCHAR2,
    p_input_cenario       IN  VARCHAR2,
    p_input_empresa    IN  NUMBER)
AS

v_s_cod_cenario TBL_APPLICATION.COD_CENARIO%TYPE;
v_n_ano_base    TBL_APPLICATION.ANO_BASE%TYPE;
v_contador_cenarios NUMBER(2);
v_verificar_cenario_arquivo VARCHAR2(40);
v_contador_commit NUMBER(8);
v_contador_colunas NUMBER(2);
--
BEGIN  
  EXECUTE IMMEDIATE 'alter session set NLS_NUMERIC_CHARACTERS = '',.''';
  --Verifica se cenário informado pela aplicação existe
  BEGIN
    SELECT COD_CENARIO
      INTO v_s_cod_cenario
      FROM TBL_APPLICATION
     WHERE COD_CENARIO = p_input_cenario
       AND COD_EMPRESA_FW   = p_input_empresa;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    PRC_ADD_ERROS(P_RESULT_ID, 'Cenário inexistente', 'DOCS');
    p_result_error := 'Erro durante a integração';
  END;
  
  ----Verifica se cenário informado no arquivo existe
  BEGIN
    SELECT COD_CENARIO INTO v_verificar_cenario_arquivo 
            FROM TBL_APPLICATION CEN WHERE CEN.COD_CENARIO IN(SELECT trim(SUBSTR(txt.DES_LINHA, 1, INSTR(txt.DES_LINHA, chr(59), 1,1) - 1)) COD_CENARIO
                            FROM TBL_APPLICATION_DADOS_TXT TXT
                            WHERE COD_PROCESSO = p_result_id AND  COD_EMPRESA_FW = p_input_empresa AND   SEQ_LINHA > 1);
    
    IF v_verificar_cenario_arquivo IS NULL THEN
        PRC_ADD_ERROS(P_RESULT_ID, 'Cenário inexistente', 'DOCS');
        p_result_error := 'Erro durante a integração';
    END IF;
  EXCEPTION WHEN NO_DATA_FOUND THEN
    PRC_ADD_ERROS(P_RESULT_ID, 'Cenário inexistente', 'DOCS');
    p_result_error := 'Erro durante a integração';
  END;

  --Verifica se existe mais de um cenário no arquivo
  BEGIN
    SELECT COUNT(DISTINCT(COD_CENARIO)) INTO v_contador_cenarios 
            FROM (SELECT trim(SUBSTR(txt.DES_LINHA, 1, INSTR(txt.DES_LINHA, chr(59), 1,1) - 1)) COD_CENARIO
                            FROM TBL_APPLICATION_DADOS_TXT TXT
                            WHERE COD_PROCESSO = p_result_id AND  COD_EMPRESA_FW = p_input_empresa AND   SEQ_LINHA > 1
                            ORDER BY SEQ_LINHA);

    IF v_contador_cenarios > 1 THEN
        PRC_ADD_ERROS(P_RESULT_ID, 'Existe mais de um cenário no arquivo', 'DOCS');
        p_result_error := 'Erro durante a integração';
    END IF;
  END;

  IF p_result_error IS NULL THEN --1
    v_contador_commit := 0;
    FOR C_TXT IN (SELECT SEQ_LINHA,
                         trim(SUBSTR(txt.DES_LINHA, 1, INSTR(txt.DES_LINHA, chr(59), 1,1) - 1)) COD_CENARIO,
                         trim(SUBSTR(txt.DES_LINHA, INSTR(txt.DES_LINHA, chr(59), 1,1) + 1, INSTR(txt.DES_LINHA, chr(59), 1,2) - INSTR(txt.DES_LINHA, chr(59), 1,1) - 1)) ESTABELECIMENTO,
                         trim(SUBSTR(txt.DES_LINHA, INSTR(txt.DES_LINHA, chr(59), 1,2) + 1, INSTR(txt.DES_LINHA, chr(59), 1,3) - INSTR(txt.DES_LINHA, chr(59), 1,2) - 1)) SERIE,
                         trim(SUBSTR(txt.DES_LINHA, INSTR(txt.DES_LINHA, chr(59), 1,3) + 1, INSTR(txt.DES_LINHA, chr(59), 1,4) - INSTR(txt.DES_LINHA, chr(59), 1,3) - 1)) NUM_DOC_SAIDA,
                         trim(SUBSTR(txt.DES_LINHA, INSTR(txt.DES_LINHA, chr(59), 1,4) + 1, INSTR(txt.DES_LINHA, chr(59), 1,5) - INSTR(txt.DES_LINHA, chr(59), 1,4) - 1)) COD_CLIENTE,
                         trim(SUBSTR(txt.DES_LINHA, INSTR(txt.DES_LINHA, chr(59), 1,5) + 1, INSTR(txt.DES_LINHA, chr(59), 1,6) - INSTR(txt.DES_LINHA, chr(59), 1,5) - 1)) DATA_EMISSAO,
                         trim(SUBSTR(txt.DES_LINHA, INSTR(txt.DES_LINHA, chr(59), 1,6) + 1, INSTR(txt.DES_LINHA, chr(59), 1,7) - INSTR(txt.DES_LINHA, chr(59), 1,6) - 1)) NATUREZA_OPERACAO,
                         trim(SUBSTR(txt.DES_LINHA, INSTR(txt.DES_LINHA, chr(59), 1,7) + 1, INSTR(txt.DES_LINHA, chr(59), 1,8) - INSTR(txt.DES_LINHA, chr(59), 1,7) - 1)) CFOP,
                         trim(SUBSTR(txt.DES_LINHA, INSTR(txt.DES_LINHA, chr(59), 1,8) + 1)) NUM_DUE_PECEX
                  FROM TBL_APPLICATION_DADOS_TXT TXT
                  WHERE COD_PROCESSO = p_result_id 
                  AND   COD_EMPRESA_FW = p_input_empresa
                  AND   SEQ_LINHA > 1
                  ORDER BY SEQ_LINHA) LOOP

       BEGIN

		--Verifica se o arquivo possui mais de 9 colunas
        BEGIN 
            SELECT INSTR(txt.DES_LINHA, chr(59), 1,9) INTO v_contador_colunas
                  FROM TBL_APPLICATION_DADOS_TXT TXT
                  WHERE COD_PROCESSO = p_result_id
                  AND   COD_EMPRESA_FW = p_input_empresa
                  AND   SEQ_LINHA = C_TXT.SEQ_LINHA
                  ORDER BY SEQ_LINHA;

            IF v_contador_colunas > 0 THEN
                PRC_ADD_ERROS(P_RESULT_ID, 'O arquivo possui o layout incorreto. Layout correto 9 colunas. Linha: '|| C_TXT.SEQ_LINHA , 'DOCS');
                p_result_error := 'Erro durante a integração';
            END IF;
        END;

        IF v_contador_colunas = 0 THEN
            BEGIN
                UPDATE TBL_APPLICATION_DOCUMENTO DOCS
                SET
                    DOCS.NUM_DUE_PECEX = C_TXT.NUM_DUE_PECEX
                WHERE
                        DOCS.COD_CENARIO = C_TXT.COD_CENARIO
                    AND DOCS.COD_ESTABEL = C_TXT.ESTABELECIMENTO
                    AND DOCS.SERIE = C_TXT.SERIE
                    AND DOCS.NR_DOC_SAIDA = C_TXT.NUM_DOC_SAIDA
                    AND DOCS.COD_CLIENTE = C_TXT.COD_CLIENTE
                    AND DOCS.DAT_EMIS_DOC = TO_DATE(C_TXT.DATA_EMISSAO, 'dd/mm/yyyy')
                    AND DOCS.NAT_OPERACAO = C_TXT.NATUREZA_OPERACAO
                    AND DOCS.CFOP = C_TXT.CFOP;

                    COMMIT;
                    v_contador_commit := v_contador_commit + 1;
              EXCEPTION
                WHEN OTHERS THEN
                  PRC_ADD_ERROS(P_RESULT_ID, 'ERRO na leitura do  arquivo na linha '|| C_TXT.SEQ_LINHA||' '||SQLERRM, 'DOCS');
                  p_result_error := 'Erro durante a integração';
                  ROLLBACK;
                  RETURN;
              END;
          END IF;
      END;
    END LOOP;

    IF v_contador_commit > 0 THEN
        PRC_ADD_MSG_SUCESSO(P_RESULT_ID, 'Foram atualizados: '|| v_contador_commit|| ' documentos', 'DOCS', 0);
    END IF;

  END IF;
END PRC_ATUALIZA_DOCUMENTOS;