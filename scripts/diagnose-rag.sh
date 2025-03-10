        log_info "Gateway Health-Info: $GW_HEALTH"
    fi
fi

echo
log_info "Bei Problemen mit dem Gateway:"
log_debug "1. Überprüfen Sie die Logs: docker logs rag-gateway"
log_debug "2. Starten Sie es neu: docker restart rag-gateway"
log_debug "3. Führen Sie eine ausführliche Diagnose durch: $0 -v"