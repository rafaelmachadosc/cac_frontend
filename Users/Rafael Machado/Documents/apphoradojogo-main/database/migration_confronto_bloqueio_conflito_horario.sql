-- Reforça no backend o bloqueio de conflito por horário + local + espaço.

ALTER TABLE public.confronto_solicitacoes
  ADD COLUMN IF NOT EXISTS local_chave text;
ALTER TABLE public.confronto_solicitacoes
  ADD COLUMN IF NOT EXISTS espaco_numero integer;
ALTER TABLE public.confronto_solicitacoes
  ADD COLUMN IF NOT EXISTS data_fim timestamptz;
ALTER TABLE public.confronto_solicitacoes
  ADD COLUMN IF NOT EXISTS duracao_minutos integer;

CREATE INDEX IF NOT EXISTS confronto_local_horario_idx
  ON public.confronto_solicitacoes (
    coalesce(local_chave, lower(trim(local_texto))),
    coalesce(espaco_numero, 0),
    data_hora
  );

CREATE OR REPLACE FUNCTION public.confronto_bloquear_conflito_horario()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  novo_inicio timestamptz;
  novo_fim timestamptz;
  existe_id uuid;
BEGIN
  IF NEW.status IN ('RECUSADO', 'CANCELADO') THEN
    RETURN NEW;
  END IF;

  novo_inicio := NEW.data_hora;
  novo_fim := coalesce(
    NEW.data_fim,
    NEW.data_hora + make_interval(mins => coalesce(NEW.duracao_minutos, 60))
  );

  SELECT c.id
    INTO existe_id
    FROM public.confronto_solicitacoes c
   WHERE c.id <> coalesce(NEW.id, '00000000-0000-0000-0000-000000000000'::uuid)
     AND c.status IN ('PENDENTE', 'ACEITO', 'CONFIRMADO')
     AND coalesce(c.local_chave, lower(trim(c.local_texto)))
         = coalesce(NEW.local_chave, lower(trim(NEW.local_texto)))
     AND coalesce(c.espaco_numero, 0) = coalesce(NEW.espaco_numero, 0)
     AND tstzrange(
           c.data_hora,
           coalesce(
             c.data_fim,
             c.data_hora + make_interval(mins => coalesce(c.duracao_minutos, 60))
           ),
           '[)'
         ) && tstzrange(novo_inicio, novo_fim, '[)')
   LIMIT 1;

  IF existe_id IS NOT NULL THEN
    RAISE EXCEPTION 'HORARIO_LOCAL_ESPACO_OCUPADO'
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_confronto_bloquear_conflito_horario
  ON public.confronto_solicitacoes;

CREATE TRIGGER tr_confronto_bloquear_conflito_horario
BEFORE INSERT OR UPDATE OF data_hora, data_fim, duracao_minutos, local_texto, local_chave, espaco_numero, status
ON public.confronto_solicitacoes
FOR EACH ROW
EXECUTE FUNCTION public.confronto_bloquear_conflito_horario();
